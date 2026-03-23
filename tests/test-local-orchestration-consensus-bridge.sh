#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/run-local-orchestration.sh"

grep -Fq 'CONSENSUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"' "${SCRIPT}" || {
  echo "FAIL: local orchestration missing kernel consensus script dependency" >&2
  exit 1
}
grep -Fq 'bash "${CONSENSUS_SCRIPT}" from-local-orchestration' "${SCRIPT}" || {
  echo "FAIL: local orchestration does not record consensus evidence from integrated.json" >&2
  exit 1
}
grep -Fq -- '- local consensus receipt: ${consensus_receipt_path:-not-recorded}' "${SCRIPT}" || {
  echo "FAIL: local orchestration summary missing consensus receipt visibility" >&2
  exit 1
}

echo "PASS [local-orchestration-consensus-bridge]"
