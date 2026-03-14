#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF_SCRIPT="${SCRIPT_DIR}/scripts/harness/fugue-bridge-handoff.sh"
TMP_ROOT="${TMPDIR:-/tmp}"
mkdir -p "${TMP_ROOT}"
TMP_DIR="$(mktemp -d "${TMP_ROOT%/}/fugue-bridge-handoff.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ ! -x "${HANDOFF_SCRIPT}" ]]; then
  echo "FAIL: missing executable script ${HANDOFF_SCRIPT}" >&2
  exit 1
fi

dry_run_cmd="$(
  bash "${HANDOFF_SCRIPT}" \
    --repo "cursorvers/fugue-orchestrator" \
    --issue-number "321" \
    --dispatch-nonce "nonce-dry-run" \
    --trust-subject "masayuki" \
    --vote-instruction-b64 "dm90ZQ==" \
    --requested-execution-mode "review" \
    --implement-request "false" \
    --implement-confirmed "false" \
    --content-hint-applied "true" \
    --content-action-hint "notebooklm-visual-brief" \
    --content-skill-hint "notebooklm-visual-brief" \
    --content-reason "notebooklm-visual-request" \
    --vote-command "true" \
    --intake-source "github-vote-comment" \
    --allow-processing-rerun \
    --dry-run
)"

for expected in \
  "workflow" \
  "run" \
  "fugue-tutti-caller.yml" \
  "issue_number=321" \
  "dispatch_nonce=nonce-dry-run" \
  "handoff_target=fugue-bridge" \
  "trust_subject=masayuki" \
  "vote_instruction_b64=dm90ZQ==" \
  "requested_execution_mode=review" \
  "implement_request=false" \
  "implement_confirmed=false" \
  "content_hint_applied=true" \
  "content_action_hint=notebooklm-visual-brief" \
  "content_skill_hint=notebooklm-visual-brief" \
  "content_reason=notebooklm-visual-request" \
  "vote_command=true" \
  "intake_source=github-vote-comment" \
  "allow_processing_rerun=true"
do
  if [[ "${dry_run_cmd}" != *"${expected}"* ]]; then
    echo "FAIL: dry-run command missing '${expected}'" >&2
    exit 1
  fi
done
echo "PASS [dry-run-command]"

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
FAKE_GH_LOG="${TMP_DIR}/gh.log"
cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${FAKE_GH_LOG}"
EOF
chmod +x "${FAKE_BIN}/gh"

runtime_output="$(
  PATH="${FAKE_BIN}:${PATH}" \
  FAKE_GH_LOG="${FAKE_GH_LOG}" \
  bash "${HANDOFF_SCRIPT}" \
    --repo "cursorvers/fugue-orchestrator" \
    --issue-number "654" \
    --dispatch-nonce "nonce-runtime" \
    --requested-execution-mode "implement" \
    --implement-request "true" \
    --implement-confirmed "true" \
    --content-hint-applied "true" \
    --content-action-hint "notebooklm-slide-prep" \
    --content-skill-hint "notebooklm-slide-prep" \
    --content-reason "notebooklm-slide-prep-request" \
    --vote-command "true" \
    --intake-source "github-vote-comment"
)"

if [[ "${runtime_output}" != *"handoff_target=fugue-bridge"* ]]; then
  echo "FAIL: runtime output missing handoff_target marker" >&2
  exit 1
fi
if [[ "${runtime_output}" != *"workflow_file=fugue-tutti-caller.yml"* ]]; then
  echo "FAIL: runtime output missing workflow marker" >&2
  exit 1
fi
if [[ ! -f "${FAKE_GH_LOG}" ]]; then
  echo "FAIL: fake gh invocation log missing" >&2
  exit 1
fi
logged_cmd="$(cat "${FAKE_GH_LOG}")"
for expected in \
  "workflow run fugue-tutti-caller.yml" \
  "--repo cursorvers/fugue-orchestrator" \
  "-f issue_number=654" \
  "-f dispatch_nonce=nonce-runtime" \
  "-f handoff_target=fugue-bridge" \
  "-f requested_execution_mode=implement" \
  "-f implement_request=true" \
  "-f implement_confirmed=true" \
  "-f content_hint_applied=true" \
  "-f content_action_hint=notebooklm-slide-prep" \
  "-f content_skill_hint=notebooklm-slide-prep" \
  "-f content_reason=notebooklm-slide-prep-request" \
  "-f vote_command=true" \
  "-f intake_source=github-vote-comment"
do
  if [[ "${logged_cmd}" != *"${expected}"* ]]; then
    echo "FAIL: runtime invocation missing '${expected}'" >&2
    exit 1
  fi
done
echo "PASS [runtime-dispatch]"

CALLER_WORKFLOW="${SCRIPT_DIR}/.github/workflows/fugue-tutti-caller.yml"
IMPLEMENT_WORKFLOW="${SCRIPT_DIR}/.github/workflows/fugue-codex-implement.yml"
ROUTER_WORKFLOW="${SCRIPT_DIR}/.github/workflows/fugue-tutti-router.yml"
CODEX_SCRIPT="${SCRIPT_DIR}/scripts/harness/codex-execute-validate.sh"

grep -q "FUGUE_LEGACY_MAIN_ORCHESTRATOR_PROVIDER" "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing legacy bridge main provider override" >&2
  exit 1
}
grep -Fq 'handoff_target: "${{ needs.ctx.outputs.handoff_target }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing handoff_target passthrough" >&2
  exit 1
}
grep -Fq 'vote_command: "${{ needs.ctx.outputs.vote_command }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing vote_command passthrough" >&2
  exit 1
}
grep -Fq 'requested_execution_mode: "${{ github.event.inputs.requested_execution_mode || '\'''\'' }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing requested_execution_mode passthrough to router" >&2
  exit 1
}
grep -Fq 'implement_request: "${{ needs.ctx.outputs.has_implement_request }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing implement_request passthrough to router" >&2
  exit 1
}
grep -Fq 'implement_confirmed: "${{ needs.ctx.outputs.has_implement_confirmed }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing implement_confirmed passthrough to router" >&2
  exit 1
}
grep -Fq 'content_hint_applied: "${{ needs.ctx.outputs.content_hint_applied }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing content_hint_applied passthrough" >&2
  exit 1
}
grep -Fq 'content_action_hint: "${{ needs.ctx.outputs.content_action_hint }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing content_action_hint passthrough" >&2
  exit 1
}
grep -Fq 'content_skill_hint: "${{ needs.ctx.outputs.content_skill_hint }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing content_skill_hint passthrough" >&2
  exit 1
}
grep -Fq 'content_reason: "${{ needs.ctx.outputs.content_reason }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing content_reason passthrough" >&2
  exit 1
}
grep -q 'content_hint_applied:' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing content_hint_applied input" >&2
  exit 1
}
grep -q 'Run NotebookLM content preflight' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing NotebookLM preflight step" >&2
  exit 1
}
grep -q 'notebooklm-preflight-enrich.sh' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing NotebookLM preflight script" >&2
  exit 1
}
grep -Fq 'NOTEBOOKLM_REPORT_PATH: ${{ steps.notebooklm_preflight.outputs.notebooklm_report_path }}' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing NotebookLM report env handoff" >&2
  exit 1
}
grep -Fq 'CONTENT_HINT_APPLIED: ${{ inputs.content_hint_applied }}' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing content hint env handoff" >&2
  exit 1
}
grep -Fq 'CONTENT_ACTION_HINT: ${{ inputs.content_action_hint }}' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing content action env handoff" >&2
  exit 1
}
grep -Fq 'CONTENT_REASON: ${{ inputs.content_reason }}' "${IMPLEMENT_WORKFLOW}" || {
  echo "FAIL: implement workflow missing content reason env handoff" >&2
  exit 1
}
grep -q 'notebooklm-slide-prep' "${CODEX_SCRIPT}" || {
  echo "FAIL: codex execute script missing notebooklm routing guidance" >&2
  exit 1
}
grep -q 'NotebookLM peripheral evidence' "${CODEX_SCRIPT}" || {
  echo "FAIL: codex execute script missing NotebookLM evidence section" >&2
  exit 1
}
grep -Fq 'intake_source: "${{ needs.ctx.outputs.intake_source }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing intake_source passthrough" >&2
  exit 1
}
grep -q 'legacy_bridge_active="true"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing legacy bridge activation path" >&2
  exit 1
}
grep -q 'multi_agent_mode_source="legacy-bridge"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing legacy bridge topology source marker" >&2
  exit 1
}
grep -q 'echo "vote_command=${vote_command}"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing vote_command output emission" >&2
  exit 1
}
grep -q '^      requested_execution_mode:' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing requested_execution_mode workflow_call input" >&2
  exit 1
}
grep -q '^      implement_request:' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing implement_request workflow_call input" >&2
  exit 1
}
grep -Fq "IMPLEMENT_REQUEST_INPUT: \${{ inputs.implement_request || '' }}" "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing implement_request env wiring" >&2
  exit 1
}
grep -q 'HAS_IMPLEMENT_REQUEST="\${implement_request_input}"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing implement_request override logic" >&2
  exit 1
}
grep -q 'echo "intake_source=${intake_source}"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing intake_source output emission" >&2
  exit 1
}
echo "PASS [workflow-wiring]"

echo "=== Results: 3/3 passed, 0 failed ==="
