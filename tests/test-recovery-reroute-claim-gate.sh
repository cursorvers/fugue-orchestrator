#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/run-recovery-console.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recovery-reroute-claim.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
FAKE_GH_LOG="${TMP_DIR}/gh.log"
CLAIM_STATE_FILE="${TMP_DIR}/claim-state.json"
ISSUE_JSON_FILE="${TMP_DIR}/issue.json"
WORKFLOW_MARKER="${TMP_DIR}/workflow-marker"
SUMMARY_FILE="${TMP_DIR}/summary.md"

cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_GH_LOG}"

if [[ "${1:-}" == "variable" && "${2:-}" == "list" ]]; then
  printf '[]\n'
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == *"/actions/variables/FUGUE_RECONCILE_CLAIM_STATE" ]]; then
  cat "${CLAIM_STATE_FILE}"
  exit 0
fi

if [[ "${1:-}" == "variable" && "${2:-}" == "set" && "${3:-}" == "FUGUE_RECONCILE_CLAIM_STATE" ]]; then
  body='{}'
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)
        body="${2:-"{}"}"
        shift 2
        ;;
      *)
        shift 1
        ;;
    esac
  done
  printf '%s' "${body}" > "${CLAIM_STATE_FILE}"
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == *"/issues/123" ]]; then
  cat "${ISSUE_JSON_FILE}"
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == *"/actions/runs?per_page=100" ]]; then
  if [[ -f "${WORKFLOW_MARKER}" ]]; then
    workflow_file="$(cat "${WORKFLOW_MARKER}")"
    jq -cn --arg wf "${workflow_file}" '
      {
        workflow_runs: [
          {
            id: 200,
            event: "workflow_dispatch",
            path: (".github/workflows/" + $wf),
            html_url: "https://github.com/cursorvers/fugue-orchestrator/actions/runs/200",
            display_title: "Recovery reroute",
            status: "queued",
            conclusion: null,
            created_at: "2026-03-09T00:00:00Z",
            name: $wf
          }
        ]
      }
    '
  else
    printf '{"workflow_runs":[]}\n'
  fi
  exit 0
fi

if [[ "${1:-}" == "workflow" && "${2:-}" == "run" ]]; then
  if [[ "${FAIL_WORKFLOW_RUN:-false}" == "true" ]]; then
    exit 1
  fi
  printf '%s' "${3:-unknown}" > "${WORKFLOW_MARKER}"
  exit 0
fi

exit 0
EOF
chmod +x "${FAKE_BIN}/gh"

run_case() {
  local name="$1"
  local claim_state_json="$2"
  local issue_labels_json="$3"
  local fail_workflow_run="${4:-false}"

  : > "${FAKE_GH_LOG}"
  : > "${SUMMARY_FILE}"
  rm -f "${WORKFLOW_MARKER}"
  printf '%s' "${claim_state_json}" > "${CLAIM_STATE_FILE}"
  jq -cn --argjson labels "${issue_labels_json}" '
    {number:123, labels:($labels | map({name:.}))}
  ' > "${ISSUE_JSON_FILE}"

  (
    cd "${ROOT_DIR}"
    env \
      PATH="${FAKE_BIN}:${PATH}" \
      FAKE_GH_LOG="${FAKE_GH_LOG}" \
      CLAIM_STATE_FILE="${CLAIM_STATE_FILE}" \
      ISSUE_JSON_FILE="${ISSUE_JSON_FILE}" \
      WORKFLOW_MARKER="${WORKFLOW_MARKER}" \
      GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
      GITHUB_STEP_SUMMARY="${SUMMARY_FILE}" \
      RECOVERY_MODE="reroute-issue" \
      RECOVERY_ISSUE_NUMBER="123" \
      RECOVERY_HANDOFF_TARGET="kernel" \
      RECOVERY_OFFLINE_POLICY="continuity" \
      RECOVERY_TRUST_SUBJECT="masayuki" \
      RECOVERY_DISPATCH_NONCE="recovery-nonce" \
      FAIL_WORKFLOW_RUN="${fail_workflow_run}" \
      FUGUE_GH_RETRY_MAX_SLEEP_SEC="1" \
      bash "${SCRIPT}" >/dev/null
  )
}

echo "=== recovery-reroute-claim-gate.sh unit tests ==="
echo ""

run_case \
  "active-claim-skip" \
  '{"claims":{"123":{"issue_number":123,"claimed_at":100,"expires_at":9999999999,"source":"watchdog-reconcile","status":"claimed"}}}' \
  '["fugue-task"]' \
  "false"
grep -Fq 'active claim already exists; reroute skipped' "${SUMMARY_FILE}" || {
  echo "FAIL [active-claim-skip]: summary missing skip note" >&2
  exit 1
}
if grep -Fq 'workflow run' "${FAKE_GH_LOG}"; then
  echo "FAIL [active-claim-skip]: dispatch should not run while claim is active" >&2
  exit 1
fi
echo "PASS [active-claim-skip]"

run_case "claim-free-dispatch" '{}' '["fugue-task"]' "false"
grep -Fq 'workflow run fugue-caller.yml' "${FAKE_GH_LOG}" || {
  echo "FAIL [claim-free-dispatch]: missing router dispatch" >&2
  exit 1
}
jq -e '.claims["123"].issue_number == 123' "${CLAIM_STATE_FILE}" >/dev/null 2>&1 || {
  echo "FAIL [claim-free-dispatch]: claim state was not persisted" >&2
  cat "${CLAIM_STATE_FILE}" >&2
  exit 1
}
echo "PASS [claim-free-dispatch]"

run_case "dispatch-failure-releases-claim" '{}' '["fugue-task"]' "true"
grep -Fq 'workflow run fugue-caller.yml' "${FAKE_GH_LOG}" || {
  echo "FAIL [dispatch-failure-releases-claim]: missing attempted router dispatch" >&2
  exit 1
}
jq -e '.claims == {}' "${CLAIM_STATE_FILE}" >/dev/null 2>&1 || {
  echo "FAIL [dispatch-failure-releases-claim]: failed dispatch left claim behind" >&2
  cat "${CLAIM_STATE_FILE}" >&2
  exit 1
}
echo "PASS [dispatch-failure-releases-claim]"

grep -Fq "failed_issue_numbers_json='[]'" "${SCRIPT}" || {
  echo "FAIL [dispatch-failure-tracking-wired]: missing failed issue tracking" >&2
  exit 1
}
grep -Fq 'reduce $failed[] as $issue ($state; .claims |= (del(.[($issue|tostring)])))' "${SCRIPT}" || {
  echo "FAIL [dispatch-failure-tracking-wired]: missing failed dispatch claim release" >&2
  exit 1
}
echo "PASS [dispatch-failure-tracking-wired]"

echo ""
echo "=== Results: 4/4 passed, 0 failed ==="
