#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-task-router.yml"
TUTTI_ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml"

mkdir -p "/Users/masayuki/Dev/tmp"
TMP_DIR="$(mktemp -d "/Users/masayuki/Dev/tmp/router-invalid-issue.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

extract_resolve_issue_context_run() {
  local workflow_file="$1"
  awk '
    $0 == "      - name: Resolve issue context" { in_step=1; next }
    in_step && $0 == "        run: |" { in_run=1; next }
    in_run && /^      - name: / { exit }
    in_run {
      sub(/^          /, "")
      print
    }
  ' "${workflow_file}"
}

FAKE_GH="${TMP_DIR}/gh"
FAKE_GH_LOG="${TMP_DIR}/gh.log"
cat > "${FAKE_GH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_GH_LOG:?}"
echo "gh should not be called for invalid issue number" >&2
exit 97
EOF
chmod +x "${FAKE_GH}"

run_task_router_case() {
  local output_file="${TMP_DIR}/task.out"
  local script_file="${TMP_DIR}/task-router-resolve.sh"
  extract_resolve_issue_context_run "${TASK_ROUTER_WORKFLOW}" > "${script_file}"
  chmod +x "${script_file}"
  : > "${FAKE_GH_LOG}"

  env \
    PATH="${TMP_DIR}:/usr/bin:/bin:/usr/sbin:/sbin" \
    FAKE_GH_LOG="${FAKE_GH_LOG}" \
    GITHUB_OUTPUT="${output_file}" \
    GITHUB_EVENT_NAME="workflow_dispatch" \
    GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
    ISSUE_NUMBER_WORKFLOW_DISPATCH="12x" \
    ISSUE_NUMBER_WORKFLOW_CALL="" \
    GITHUB_EVENT_PATH="${TMP_DIR}/event.json" \
    bash "${script_file}" >/dev/null

  grep -Fxq 'should_run=false' "${output_file}" || {
    echo "FAIL: task router should reject malformed issue number with should_run=false" >&2
    cat "${output_file}" >&2
    exit 1
  }
  grep -Fxq 'skip_reason=invalid-issue-number' "${output_file}" || {
    echo "FAIL: task router should emit invalid-issue-number skip reason" >&2
    cat "${output_file}" >&2
    exit 1
  }
  if [[ -s "${FAKE_GH_LOG}" ]]; then
    echo "FAIL: task router should not call gh api for malformed issue number" >&2
    cat "${FAKE_GH_LOG}" >&2
    exit 1
  fi
  echo "PASS [task-router-invalid-issue-number]"
}

run_tutti_router_case() {
  local output_file="${TMP_DIR}/tutti.out"
  local script_file="${TMP_DIR}/tutti-router-resolve.sh"
  extract_resolve_issue_context_run "${TUTTI_ROUTER_WORKFLOW}" > "${script_file}"
  chmod +x "${script_file}"
  : > "${FAKE_GH_LOG}"

  env \
    PATH="${TMP_DIR}:/usr/bin:/bin:/usr/sbin:/sbin" \
    FAKE_GH_LOG="${FAKE_GH_LOG}" \
    GITHUB_OUTPUT="${output_file}" \
    GITHUB_EVENT_NAME="workflow_call" \
    GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
    ISSUE_NUMBER_INPUT="12x" \
    TRUST_SUBJECT_INPUT="" \
    CANARY_DISPATCH_OWNED_INPUT="false" \
    ALLOW_PROCESSING_RERUN_INPUT="false" \
    SUBSCRIPTION_OFFLINE_POLICY_OVERRIDE_INPUT="" \
    EXTRA_ISSUE_INSTRUCTION_INPUT="" \
    VOTE_COMMAND_INPUT="false" \
    INTAKE_SOURCE_INPUT="" \
    CI_EXECUTION_ENGINE="subscription" \
    SUBSCRIPTION_OFFLINE_POLICY="continuity" \
    EMERGENCY_CONTINUITY_MODE="false" \
    SUBSCRIPTION_RUNNER_LABEL="fugue-subscription" \
    GITHUB_EVENT_PATH="${TMP_DIR}/event.json" \
    bash "${script_file}" >/dev/null

  grep -Fxq 'should_run=false' "${output_file}" || {
    echo "FAIL: tutti router should reject malformed issue number with should_run=false" >&2
    cat "${output_file}" >&2
    exit 1
  }
  grep -Fxq 'skip_reason=invalid-issue-number' "${output_file}" || {
    echo "FAIL: tutti router should emit invalid-issue-number skip reason" >&2
    cat "${output_file}" >&2
    exit 1
  }
  if [[ -s "${FAKE_GH_LOG}" ]]; then
    echo "FAIL: tutti router should not call gh api for malformed issue number" >&2
    cat "${FAKE_GH_LOG}" >&2
    exit 1
  fi
  echo "PASS [tutti-router-invalid-issue-number]"
}

printf '%s\n' '{}' > "${TMP_DIR}/event.json"

run_task_router_case
run_tutti_router_case
