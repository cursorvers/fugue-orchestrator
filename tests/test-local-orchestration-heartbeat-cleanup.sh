#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/run-local-orchestration.sh"

grep -Fq 'trap restore_primary_heartbeat EXIT' "${SCRIPT}" || {
  echo "FAIL: local orchestration missing EXIT heartbeat restore trap" >&2
  exit 1
}
grep -Fq 'if [[ "${primary_heartbeat_busy}" != "true" ]]; then' "${SCRIPT}" || {
  echo "FAIL: local orchestration missing busy-state heartbeat restore guard" >&2
  exit 1
}
grep -Fq 'primary_heartbeat_busy="true"' "${SCRIPT}" || {
  echo "FAIL: local orchestration missing busy heartbeat marker" >&2
  exit 1
}
grep -Fq 'primary_heartbeat_busy="false"' "${SCRIPT}" || {
  echo "FAIL: local orchestration missing online heartbeat reset marker" >&2
  exit 1
}

echo "PASS [local-orchestration-heartbeat-cleanup]"
