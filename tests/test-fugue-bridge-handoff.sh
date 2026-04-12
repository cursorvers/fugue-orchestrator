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
    --subscription-offline-policy-override "continuity" \
    --implement-request "false" \
    --implement-confirmed "false" \
    --vote-command "true" \
    --intake-source "github-vote-comment" \
    --execution-mode-override "backup-heavy" \
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
  "subscription_offline_policy_override=continuity" \
  "implement_request=false" \
  "implement_confirmed=false" \
  "vote_command=true" \
  "intake_source=github-vote-comment" \
  "execution_mode_override=backup-heavy" \
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
    --vote-command "true" \
    --intake-source "github-vote-comment" \
    --execution-mode-override "primary"
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
  "-f vote_command=true" \
  "-f intake_source=github-vote-comment" \
  "-f execution_mode_override=primary"
do
  if [[ "${logged_cmd}" != *"${expected}"* ]]; then
    echo "FAIL: runtime invocation missing '${expected}'" >&2
    exit 1
  fi
done
echo "PASS [runtime-dispatch]"

CALLER_WORKFLOW="${SCRIPT_DIR}/.github/workflows/fugue-tutti-caller.yml"
ROUTER_WORKFLOW="${SCRIPT_DIR}/.github/workflows/fugue-tutti-router.yml"

grep -q "FUGUE_LEGACY_MAIN_ORCHESTRATOR_PROVIDER" "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing legacy bridge main provider override" >&2
  exit 1
}
grep -q 'handoff_target: "\${{ needs.ctx.outputs.handoff_target }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing handoff_target passthrough" >&2
  exit 1
}
grep -q 'vote_command: "\${{ needs.ctx.outputs.vote_command }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing vote_command passthrough" >&2
  exit 1
}
grep -q 'intake_source: "\${{ needs.ctx.outputs.intake_source }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing intake_source passthrough" >&2
  exit 1
}
grep -q 'execution_mode: "\${{ needs.execution-policy.outputs.codex_execution_mode }}"' "${CALLER_WORKFLOW}" || {
  echo "FAIL: caller workflow missing execution mode passthrough for implementation" >&2
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
grep -q 'echo "intake_source=${intake_source}"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing intake_source output emission" >&2
  exit 1
}
echo "PASS [workflow-wiring]"

echo "=== Results: 3/3 passed, 0 failed ==="
