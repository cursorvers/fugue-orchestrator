#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
MEMORY_QUERY_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-memory-query.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_RUN_ID="memory-run"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="shared-memory"
export KERNEL_PHASE="implement"
export KERNEL_OWNER="codex"
export KERNEL_TMUX_SESSION="fugue-orchestrator__shared-memory"
export KERNEL_RUNTIME="kernel"
export KERNEL_DECISIONS="bounded-handoff|repo-native-first"
export KERNEL_NEXT_ACTIONS="resume-codex-thread"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"

context_reference_path="${TMP_DIR}/context.json"
cat >"${context_reference_path}" <<'EOF'
{
  "kind": "social-post",
  "post_id": "77"
}
EOF

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" transition healthy "bootstrap-valid" >/dev/null
KERNEL_CONTEXT_REFERENCE_PATH="${context_reference_path}" \
KERNEL_CONTEXT_REFERENCE_KIND="social-post" \
KERNEL_CONTEXT_REFERENCE_LABEL="social-post #77" \
  bash "${COMPACT_SCRIPT}" update manual_snapshot "repo-native bounded handoff" >/dev/null

out="$(bash "${MEMORY_QUERY_SCRIPT}" search --format text "bounded handoff")"
grep -Fq 'matched runs: 1' <<<"${out}"
grep -Fq 'run=memory-run' <<<"${out}"

search_json="$(bash "${MEMORY_QUERY_SCRIPT}" search --format json "bounded handoff")"
[[ "$(jq -r '.results[0].phase' <<<"${search_json}")" == "implement" ]]
[[ "$(jq -r '.results[0].current_phase' <<<"${search_json}")" == "implement" ]]

packet_json="$(bash "${MEMORY_QUERY_SCRIPT}" packet --run memory-run --format json)"
grep -Fq '"run_id":"memory-run"' <<<"${packet_json}"
grep -Fq '"purpose":"shared-memory"' <<<"${packet_json}"
grep -Fq '"path":"'"${context_reference_path}"'"' <<<"${packet_json}"

packet_text="$(bash "${MEMORY_QUERY_SCRIPT}" packet "repo native" --format text)"
grep -Fq 'Kernel handoff packet:' <<<"${packet_text}"
grep -Fq 'run id: memory-run' <<<"${packet_text}"
grep -Fq "context reference: social-post #77 -> ${context_reference_path}" <<<"${packet_text}"

packet_text_unquoted="$(bash "${MEMORY_QUERY_SCRIPT}" packet repo native --format text)"
grep -Fq 'Kernel handoff packet:' <<<"${packet_text_unquoted}"
grep -Fq 'run id: memory-run' <<<"${packet_text_unquoted}"

sentinel="${TMP_DIR}/query-sentinel"
printf 'keep\n' >"${sentinel}"
set +e
bash "${MEMORY_QUERY_SCRIPT}" packet 'repo"; rm -f '"${sentinel}"'; echo "native' --format text >/dev/null 2>&1
malicious_status=$?
set -e
[[ "${malicious_status}" -ne 0 ]]
[[ -f "${sentinel}" ]]

echo "kernel memory query check passed"
