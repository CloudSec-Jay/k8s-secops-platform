#!/usr/bin/env python3
#
# executable-perm.py — Falco active response: execution allowlist gate
#
# WHAT THIS DOES
#   Triggered by Falco when chmod +x is detected on a monitored path.
#   Immediately locks the file (chattr +i) to prevent execution, then
#   decides whether to allow or block based on two checks:
#     1. Local allowlist — known-good SHA256 hashes (works offline)
#     2. Azure Logic App — approval workflow for unknown files (online)
#   Unknown files remain locked until an admin approves via Azure.
#   If the host is offline and the hash is unknown, default deny.
#
# REQUIREMENTS
#   System packages:
#     - python3          (runtime)
#     - e2fsprogs        (provides chattr — dnf install e2fsprogs)
#   Python stdlib only — no pip dependencies
#
#   Files that must exist before running:
#     - /var/ossec/etc/allowlist.json    (see ALLOWLIST FORMAT below)
#     - /var/ossec/logs/active-response/ (directory must exist, writable)
#
#   Permissions:
#     - Must run as root (chattr requires root)
#     - Falco calls this script automatically via program_output
#
#   Falco config required (falco.yaml):
#     program_output:
#       enabled: true
#       program: "/var/ossec/active-response/bin/executable-perm.py"
#
#   Falco rule required — must output fd.name and user.name fields:
#     - rule: chmod +x detected
#       output_fields: [fd.name, user.name, proc.name]
#
# ALLOWLIST FORMAT (/var/ossec/etc/allowlist.json):
#   {
#     "hashes": [
#       "abc123...",   <- SHA256 hash of an approved executable
#       "def456..."
#     ]
#   }
#   To add a hash: sha256sum /path/to/file
#
#
import sys
import json
import socket
import hashlib
import subprocess
from datetime import datetime, timezone

ALLOWLIST_PATH = "/var/ossec/etc/allowlist.json"
LOG_PATH = "/var/ossec/logs/active-response/executable-perm.log"


def read_alert():
    # Falco pipes JSON alert data to stdin
    # json.loads() converts raw string to a Python dictionary
    raw = sys.stdin.read()
    alert = json.loads(raw)

    # output_fields holds the event details from Falco
    # fd.name = file path, user.name = who ran chmod
    path = alert["output_fields"]["fd.name"]
    user = alert["output_fields"]["user.name"]

    return path, user


def is_online():
    # Try TCP connection to Google DNS on port 53
    # Succeeds = online, raises OSError = offline
    try:
        socket.create_connection(("8.8.8.8", 53), timeout=3)
        return True
    except OSError:
        return False


def hash_file(path):
    sha256 = hashlib.sha256()

    # Binary mode — hashing works on raw bytes not text
    with open(path, "rb") as f:
        # Read in chunks so large files don't fill memory
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)

    # hexdigest() returns a 64-character hex string
    return sha256.hexdigest()


def check_allowlist(file_hash):
    with open(ALLOWLIST_PATH, "r") as f:
        allowlist = json.load(f)

    # Returns True if hash found, False if not
    return file_hash in allowlist["hashes"]


def add_to_allowlist(file_hash):
    with open(ALLOWLIST_PATH, "r") as f:
        allowlist = json.load(f)

    allowlist["hashes"].append(file_hash)

    # indent=2 keeps the file human readable
    with open(ALLOWLIST_PATH, "w") as f:
        json.dump(allowlist, f, indent=2)


def lock_file(path):
    # chattr +i = immutable, even root cannot run or modify
    # list form not string — prevents command injection
    result = subprocess.run(
        ["chattr", "+i", path],
        capture_output=True,
        text=True
    )
    # returncode 0 = success
    return result.returncode == 0


def unlock_file(path):
    # chattr -i removes immutable flag before approve/deny
    result = subprocess.run(
        ["chattr", "-i", path],
        capture_output=True,
        text=True
    )
    return result.returncode == 0


def log_event(action, path, user, reason):
    timestamp = datetime.now(timezone.utc).isoformat()
    line = (
        f"{timestamp} | action={action} | file={path}"
        f" | user={user} | reason={reason}\n"
    )
    # a = append mode, creates file if it doesn't exist
    with open(LOG_PATH, "a") as f:
        f.write(line)


def main():
    # Step 1 — read what Falco sent
    path, user = read_alert()

    # Step 2 — lock immediately, ask questions later
    lock_file(path)
    log_event("locked", path, user, "chmod+x detected")

    # Step 3 — hash the file to check the allowlist
    file_hash = hash_file(path)

    # Step 4 — allowlist check regardless of online status
    if check_allowlist(file_hash):
        unlock_file(path)
        log_event("allowed", path, user, "hash in allowlist")
        sys.exit(0)

    # Step 5 — unknown file, check if Azure is reachable
    if is_online():
        # TODO: POST to Azure Logic App webhook
        log_event("pending", path, user, "unknown, awaiting Azure")
    else:
        # offline + unknown = stays locked until network restores
        log_event("blocked", path, user, "unknown, offline, deny")


if __name__ == "__main__":
    main()
