#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml"

grep -Fq 'run-agents-hosted:' "${WORKFLOW}" || {
  echo "FAIL: hosted run-agents job missing" >&2
  exit 1
}
grep -Fq "runs-on: ubuntu-latest" "${WORKFLOW}" || {
  echo "FAIL: hosted run-agents job no longer uses ubuntu-latest directly" >&2
  exit 1
}
grep -Fq "needs.resolve-orchestrator.outputs.run_agents_runner != 'self-hosted'" "${WORKFLOW}" || {
  echo "FAIL: hosted run-agents gate missing self-hosted exclusion" >&2
  exit 1
}
grep -Fq 'run-agents-self-hosted:' "${WORKFLOW}" || {
  echo "FAIL: self-hosted run-agents job missing" >&2
  exit 1
}
grep -Fq 'needs.resolve-orchestrator.outputs.run_agents_runner == '\''self-hosted'\''' "${WORKFLOW}" || {
  echo "FAIL: self-hosted run-agents gate missing" >&2
  exit 1
}
grep -Fq 'needs: [prepare, resolve-orchestrator, run-agents-hosted, run-agents-self-hosted]' "${WORKFLOW}" || {
  echo "FAIL: integrate no longer depends on both run-agents branches" >&2
  exit 1
}
grep -Fq "matrix=\"\$(echo \"\${matrix_payload}\" | jq -c '.workflow_matrix')\"" "${WORKFLOW}" || {
  echo "FAIL: router is not extracting the clean workflow_matrix payload for strategy.matrix" >&2
  exit 1
}
grep -Fq "if: \${{ always() && needs.prepare.outputs.should_run == 'true' && needs.prepare.outputs.trusted == 'true' && (needs.run-agents-hosted.result == 'success' || needs.run-agents-self-hosted.result == 'success') }}" "${WORKFLOW}" || {
  echo "FAIL: integrate gate missing hosted/self-hosted success OR condition" >&2
  exit 1
}

echo "PASS [tutti-run-agents-routing]"
