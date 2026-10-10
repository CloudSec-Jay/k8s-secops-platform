#!/usr/bin/env python3
"""Validate repository structure, syntax, local links, and architecture boundaries."""

from __future__ import annotations

import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlsplit

import yaml


ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HTML_LINK = re.compile(r"(?:href|src)=[\"']([^\"']+)[\"']")


def error(message: str) -> None:
    ERRORS.append(message)


def validate_required_files() -> None:
    required = (
        "README.md",
        "versions.env",
        "platform/kubeadm/README.md",
        "platform/cilium/values.yaml",
        "wazuh/platform/README.md",
        "wazuh/content/README.md",
        "docs/site/index.html",
    )
    for relative in required:
        if not (ROOT / relative).is_file():
            error(f"missing required file: {relative}")


def validate_structured_files() -> None:
    for path in ROOT.rglob("*.xml"):
        try:
            ET.parse(path)
        except ET.ParseError as exc:
            error(f"invalid XML: {path.relative_to(ROOT)}: {exc}")

    for suffix in ("*.yaml", "*.yml"):
        for path in ROOT.rglob(suffix):
            try:
                list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
            except yaml.YAMLError as exc:
                error(f"invalid YAML: {path.relative_to(ROOT)}: {exc}")


def local_target(source: Path, raw_target: str) -> Path | None:
    target = raw_target.strip().split(maxsplit=1)[0].strip("<>")
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or target.startswith(("#", "mailto:")):
        return None
    clean_path = unquote(parsed.path)
    if not clean_path:
        return None
    return (source.parent / clean_path).resolve()


def validate_links() -> None:
    for path in ROOT.rglob("*.md"):
        text = path.read_text(encoding="utf-8")
        for target in MARKDOWN_LINK.findall(text):
            resolved = local_target(path, target)
            if resolved is not None and not resolved.exists():
                error(f"broken link in {path.relative_to(ROOT)}: {target}")

    for path in (ROOT / "docs/site").rglob("*.html"):
        text = path.read_text(encoding="utf-8")
        for target in HTML_LINK.findall(text):
            resolved = local_target(path, target)
            if resolved is not None and not resolved.exists():
                error(f"broken site link in {path.relative_to(ROOT)}: {target}")


def validate_boundaries() -> None:
    canonical = [
        ROOT / "README.md",
        ROOT / "platform",
        ROOT / "wazuh/platform",
    ]
    banned = re.compile(r"\b(minikube|quadlet|docker[ -]compose)\b", re.IGNORECASE)
    allowed_context = {
        ROOT / "README.md",
        ROOT / "AGENTS.md",
        ROOT / "wazuh/content/README.md",
    }
    for item in canonical:
        paths = [item] if item.is_file() else [p for p in item.rglob("*") if p.is_file()]
        for path in paths:
            if path in allowed_context:
                continue
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if banned.search(line):
                    error(f"legacy runtime reference in {path.relative_to(ROOT)}:{line_number}")

    forbidden_paths = (
        ROOT / "platform/scripts/minikube_setup.sh",
        ROOT / "wazuh/deploy/wazuh_deploy",
        ROOT / "wazuh/deploy/wazuh_teardown",
        ROOT / "wazuh/content/integrations/docker",
    )
    for path in forbidden_paths:
        if path.exists():
            error(f"forbidden legacy path exists: {path.relative_to(ROOT)}")


def validate_shell() -> None:
    scripts = [ROOT / "scripts/stage-wazuh-platform.sh"]
    scripts.extend((ROOT / "wazuh/content").rglob("*.sh"))
    for path in scripts:
        result = subprocess.run(
            ["bash", "-n", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            error(f"invalid shell syntax: {path.relative_to(ROOT)}: {result.stderr.strip()}")


def main() -> int:
    validate_required_files()
    validate_structured_files()
    validate_links()
    validate_boundaries()
    validate_shell()

    if ERRORS:
        for message in ERRORS:
            print(f"ERROR: {message}", file=sys.stderr)
        return 1

    print("Repository validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
