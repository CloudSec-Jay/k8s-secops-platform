#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "${repo_root}/versions.env"

destination="${repo_root}/.cache/wazuh-kubernetes-${WAZUH_VERSION}"
upstream="https://github.com/wazuh/wazuh-kubernetes.git"

if [[ -e "${destination}" ]]; then
  if [[ -d "${destination}/.git" ]] &&
     [[ "$(git -C "${destination}" remote get-url origin)" == "${upstream}" ]] &&
     [[ "$(git -C "${destination}" describe --tags --exact-match 2>/dev/null || true)" == "${WAZUH_VERSION}" ]]; then
    printf 'Pinned Wazuh source is already staged at %s\n' "${destination}"
    exit 0
  fi

  printf 'Refusing to overwrite existing path: %s\n' "${destination}" >&2
  exit 1
fi

mkdir -p "${repo_root}/.cache"
git clone --branch "${WAZUH_VERSION}" --depth 1 "${upstream}" "${destination}"
git -C "${destination}" verify-commit HEAD 2>/dev/null || \
  printf 'Note: Git could not verify the tag commit with a locally trusted signing key.\n' >&2

printf 'Staged %s at %s\n' "${WAZUH_VERSION}" "${destination}"
printf 'Review the upstream tree, storage class, secrets, and release notes before kubectl apply.\n'
