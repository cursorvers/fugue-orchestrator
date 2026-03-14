#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq "FUGUE_CODEX_MULTI_AGENT_MODEL || 'gpt-5-codex'" "${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml" || {
  echo "FAIL: tutti caller still defaults CODEX_MULTI_AGENT_MODEL to spark" >&2
  exit 1
}
grep -Fq "FUGUE_CODEX_MULTI_AGENT_MODEL || 'gpt-5-codex'" "${ROOT_DIR}/.github/workflows/fugue-task-router.yml" || {
  echo "FAIL: task router still defaults CODEX_MULTI_AGENT_MODEL to spark" >&2
  exit 1
}
grep -Fq "FUGUE_CODEX_MULTI_AGENT_MODEL || 'gpt-5-codex'" "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router still defaults CODEX_MULTI_AGENT_MODEL to spark" >&2
  exit 1
}
grep -Fq 'echo "gpt-5-codex"' "${ROOT_DIR}/.github/workflows/fugue-status.yml" || {
  echo "FAIL: fugue-status fallback still points to spark" >&2
  exit 1
}
grep -Fq "vars.FUGUE_GLM_MODEL || 'glm-5'" "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router GLM default drifted from glm-5" >&2
  exit 1
}
grep -Fq 'GLM_MODEL="glm-5"' "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router GLM normalization fallback drifted from glm-5" >&2
  exit 1
}
grep -Fq 'run_agents_runner_json='"'"'"ubuntu-latest"'"'"'' "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router hosted runner json is no longer emitted as a JSON string" >&2
  exit 1
}
grep -Fq 'run_agents_runner_json="$(jq -cn --arg label "${subscription_runner_label}" '"'"'["self-hosted",$label]'"'"')"' "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router self-hosted runner json mapping drifted" >&2
  exit 1
}
grep -Fq 'metered_reason:' "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router is missing metered_reason workflow_call input" >&2
  exit 1
}
grep -Fq 'metered_reason: "${{ needs.ctx.outputs.metered_reason }}"' "${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml" || {
  echo "FAIL: tutti caller is not forwarding metered_reason into router" >&2
  exit 1
}
grep -Fq "METERED_PROVIDER_REASON: \${{ matrix.metered_reason || needs.prepare.outputs.metered_reason || 'none' }}" "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router does not pass lane metered reason into runner env" >&2
  exit 1
}
grep -Fq '^(gpt-5(\.[0-9]+)?-codex-spark|gpt-5-codex|gpt-5\.4)$' "${ROOT_DIR}/.github/workflows/fugue-task-router.yml" || {
  echo "FAIL: task router normalization no longer restricts CODEX_MULTI_AGENT_MODEL to codex/spark families" >&2
  exit 1
}
grep -Fq '^(gpt-5(\.[0-9]+)?-codex-spark|gpt-5-codex|gpt-5\.4)$' "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" || {
  echo "FAIL: tutti router normalization no longer restricts CODEX_MULTI_AGENT_MODEL to codex/spark families" >&2
  exit 1
}
if grep -Fq 'gpt-5.3-codex-spark' "${ROOT_DIR}/.github/workflows/codex-review.yml"; then
  echo "FAIL: codex-review workflow still auto-falls back to spark outside simulation" >&2
  exit 1
fi

echo "PASS [workflow-model-defaults]"
