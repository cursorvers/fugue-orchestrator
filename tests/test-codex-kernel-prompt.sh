#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="${ROOT_DIR}/scripts/check-codex-kernel-prompt.sh"

if [[ ! -x "${CHECK_SCRIPT}" ]]; then
  echo "FAIL: missing executable script ${CHECK_SCRIPT}" >&2
  exit 1
fi

bash "${CHECK_SCRIPT}"
