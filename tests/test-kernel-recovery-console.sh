#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/kernel-recovery-console.yml"
MOBILE_WORKFLOW="${ROOT_DIR}/.github/workflows/kernel-mobile-progress.yml"
SCRIPT="${ROOT_DIR}/scripts/harness/run-recovery-console.sh"
RUNBOOK="${ROOT_DIR}/docs/kernel-recovery-runbook.md"

grep -q -- '- mobile-progress' "${WORKFLOW}" || {
  echo "FAIL: kernel-recovery-console workflow missing mobile-progress mode" >&2
  exit 1
}
grep -q -- '- manus-diagnose' "${WORKFLOW}" || {
  echo "FAIL: kernel-recovery-console workflow missing manus-diagnose mode" >&2
  exit 1
}
grep -q 'name: kernel-mobile-progress' "${MOBILE_WORKFLOW}" || {
  echo "FAIL: missing kernel-mobile-progress workflow" >&2
  exit 1
}
grep -q 'RECOVERY_MODE: mobile-progress' "${MOBILE_WORKFLOW}" || {
  echo "FAIL: kernel-mobile-progress workflow should dispatch mobile-progress mode" >&2
  exit 1
}
grep -q 'mobile_progress()' "${SCRIPT}" || {
  echo "FAIL: recovery console script missing mobile_progress helper" >&2
  exit 1
}
grep -q 'ensure_status_issue()' "${SCRIPT}" || {
  echo "FAIL: recovery console script missing status-thread helper" >&2
  exit 1
}
grep -q 'manus_diagnose()' "${SCRIPT}" || {
  echo "FAIL: recovery console script missing manus_diagnose helper" >&2
  exit 1
}
grep -q 'manus-recovery-diagnose.js' "${SCRIPT}" || {
  echo "FAIL: manus-diagnose mode should call the Manus diagnosis helper" >&2
  exit 1
}
grep -q 'overallHealthScore' "${ROOT_DIR}/scripts/harness/manus-recovery-diagnose.js" || {
  echo "FAIL: manus diagnosis should emit an SLO-compatible health score" >&2
  exit 1
}
grep -q 'blockingCondition' "${ROOT_DIR}/scripts/harness/manus-recovery-diagnose.js" || {
  echo "FAIL: manus diagnosis should emit blocking condition telemetry" >&2
  exit 1
}
grep -q 'gh issue comment "${status_issue}"' "${SCRIPT}" || {
  echo "FAIL: mobile-progress should post into the status issue" >&2
  exit 1
}
REROUTE_BLOCK="$(sed -n '/reroute_issue()/,/^}/p' "${SCRIPT}")"
grep -q '"fugue-caller.yml"' <<<"${REROUTE_BLOCK}" || {
  echo "FAIL: reroute-issue should dispatch fugue-caller.yml" >&2
  exit 1
}
if grep -q '"fugue-task-router.yml"' <<<"${REROUTE_BLOCK}"; then
  echo "FAIL: reroute-issue should not dispatch fugue-task-router.yml directly" >&2
  exit 1
fi
grep -q 'gh workflow run fugue-caller.yml' "${ROOT_DIR}/.github/workflows/fugue-watchdog.yml" || {
  echo "FAIL: watchdog should dispatch fugue-caller.yml for pending issues" >&2
  exit 1
}
grep -q 'actions/workflows/fugue-caller.yml/runs' "${ROOT_DIR}/.github/workflows/fugue-watchdog.yml" || {
  echo "FAIL: watchdog should measure caller staleness from fugue-caller.yml" >&2
  exit 1
}
grep -q '### `mobile-progress`' "${RUNBOOK}" || {
  echo "FAIL: recovery runbook missing mobile-progress section" >&2
  exit 1
}
grep -q 'kernel-mobile-progress' "${RUNBOOK}" || {
  echo "FAIL: recovery runbook should describe automatic mobile progress publishing" >&2
  exit 1
}

TMP_ROOT="${TMPDIR:-/tmp}"
TMP_DIR="$(mktemp -d "${TMP_ROOT%/}/kernel-recovery-console.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
FAKE_GH_LOG="${TMP_DIR}/gh.log"
FAKE_SUMMARY="${TMP_DIR}/summary.md"
cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_GH_LOG}"

if [[ "${1:-}" == "api" ]]; then
  case "${2:-}" in
    repos/cursorvers/fugue-orchestrator/issues/123)
      printf '%s\n' '{"labels":[{"name":"fugue-task"},{"name":"tutti"}]}'
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/actions/runs\?per_page=100)
      if grep -q 'workflow run fugue-caller.yml' "${FAKE_GH_LOG}"; then
        printf '%s\n' '{"workflow_runs":[{"id":456,"event":"workflow_dispatch","path":".github/workflows/fugue-caller.yml","html_url":"https://github.com/cursorvers/fugue-orchestrator/actions/runs/456","created_at":"2026-03-08T00:00:00Z","display_title":"fugue-caller","name":"fugue-caller"}]}'
      else
        printf '%s\n' '{"workflow_runs":[]}'
      fi
      exit 0
      ;;
  esac
fi

exit 0
EOF
chmod +x "${FAKE_BIN}/gh"

PATH="${FAKE_BIN}:${PATH}" \
FAKE_GH_LOG="${FAKE_GH_LOG}" \
GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
GITHUB_STEP_SUMMARY="${FAKE_SUMMARY}" \
RECOVERY_MODE="reroute-issue" \
RECOVERY_ISSUE_NUMBER="123" \
RECOVERY_TRUST_SUBJECT="masayuki" \
bash "${SCRIPT}" >/dev/null

grep -q 'workflow run fugue-caller.yml' "${FAKE_GH_LOG}" || {
  echo "FAIL: reroute-issue runtime should dispatch fugue-caller.yml" >&2
  exit 1
}
grep -q -- '-f trigger_event_name=issues' "${FAKE_GH_LOG}" || {
  echo "FAIL: reroute-issue runtime should replay explicit issues trigger for tutti reroute" >&2
  exit 1
}
grep -q -- '-f trigger_label_name=tutti' "${FAKE_GH_LOG}" || {
  echo "FAIL: reroute-issue runtime should replay explicit tutti label trigger" >&2
  exit 1
}

PATH="${FAKE_BIN}:${PATH}" \
FAKE_GH_LOG="${FAKE_GH_LOG}" \
GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
GITHUB_STEP_SUMMARY="${FAKE_SUMMARY}" \
RECOVERY_MODE="manus-diagnose" \
RECOVERY_ISSUE_NUMBER="123" \
bash "${SCRIPT}" >/dev/null

grep -q 'Manus Recovery Diagnosis' "${FAKE_SUMMARY}" || {
  echo "FAIL: manus-diagnose should append a recovery diagnosis summary" >&2
  exit 1
}
grep -q 'live manus task started: `false`' "${FAKE_SUMMARY}" || {
  echo "FAIL: manus-diagnose must not start a live Manus task by default" >&2
  exit 1
}
grep -q 'health score:' "${FAKE_SUMMARY}" || {
  echo "FAIL: manus-diagnose should include health score in summary" >&2
  exit 1
}
grep -q 'blocking condition:' "${FAKE_SUMMARY}" || {
  echo "FAIL: manus-diagnose should include blocking condition in summary" >&2
  exit 1
}

echo "PASS [kernel-recovery-console-mobile-progress]"
