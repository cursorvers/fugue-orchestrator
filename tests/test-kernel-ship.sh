#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIP_SCRIPT="${ROOT_DIR}/scripts/local/kernel-ship.sh"

out="$(bash "${SHIP_SCRIPT}" status 4pane-ship)"
grep -Fq 'Kernel 4-pane ship' <<<"${out}"
grep -Fq 'run: 4pane-ship' <<<"${out}"
grep -Fq 'dry run: true' <<<"${out}"

if KERNEL_4PANE_SHIP_ENABLED=false bash "${SHIP_SCRIPT}" execute 4pane-ship >/dev/null 2>&1; then
  echo "execute should fail when ship is monitor-only" >&2
  exit 1
fi

echo "kernel ship check passed"
