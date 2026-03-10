#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/harness/resolve-googleworkspace-feed-matrix.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

policy_file="${tmp_dir}/policy.json"
cat > "${policy_file}" <<'EOF'
{
  "version": 1,
  "profiles": {
    "morning-brief-shared": {
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "shared",
      "github_environment": "workspace-readonly",
      "recommended_cron_utc": "0 21 * * 0-4"
    },
    "morning-brief-personal": {
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "personal",
      "github_environment": "workspace-personal-readonly",
      "recommended_cron_utc": "5 21 * * 0-4"
    },
    "weekly-digest-personal": {
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "personal",
      "github_environment": "workspace-personal-readonly",
      "recommended_cron_utc": "15 21 * * 0"
    },
    "pre-meeting-scan": {
      "enabled_by_default": false,
      "execution_target": "dispatch-only",
      "workflow_target": "manual",
      "github_environment": "workspace-readonly",
      "recommended_cron_utc": ""
    }
  }
}
EOF

assert_ok() {
  local test_name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${test_name}]"
    failed=$((failed + 1))
  fi
}

run_script() {
  local output_file="$1"
  shift

  env \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    GITHUB_OUTPUT="${output_file}" \
    "$@" \
    bash "${SCRIPT}" >/dev/null
}

test_schedule_selects_shared_profiles() {
  local output_file="${tmp_dir}/shared-schedule.out"
  run_script "${output_file}" \
    EVENT_NAME=schedule \
    SCHEDULE_EXPR="0 21 * * 0-4" \
    INPUT_WORKFLOW_TARGET=shared

  grep -q '^profile_count=1$' "${output_file}" &&
    jq -e '.[0].profile == "morning-brief-shared" and .[0].environment == "workspace-readonly"' \
      <(awk -F= '/^matrix=/{print $2}' "${output_file}") >/dev/null
}

test_schedule_selects_personal_profiles() {
  local output_file="${tmp_dir}/personal-schedule.out"
  run_script "${output_file}" \
    EVENT_NAME=schedule \
    SCHEDULE_EXPR="15 21 * * 0" \
    INPUT_WORKFLOW_TARGET=personal

  grep -q '^profile_count=1$' "${output_file}" &&
    jq -e '.[0].profile == "weekly-digest-personal" and .[0].environment == "workspace-personal-readonly"' \
      <(awk -F= '/^matrix=/{print $2}' "${output_file}") >/dev/null
}

test_dispatch_selects_all_personal_profiles() {
  local output_file="${tmp_dir}/personal-dispatch.out"
  run_script "${output_file}" \
    EVENT_NAME=workflow_dispatch \
    INPUT_PROFILE=all-personal \
    INPUT_WORKFLOW_TARGET=personal \
    INPUT_FORCE_REFRESH=true

  grep -q '^force_refresh=true$' "${output_file}" &&
    grep -q '^profile_count=2$' "${output_file}" &&
    jq -e 'length == 2 and all(.[]; .environment == "workspace-personal-readonly")' \
      <(awk -F= '/^matrix=/{print $2}' "${output_file}") >/dev/null
}

test_dispatch_rejects_wrong_workflow_target() {
  local output_file="${tmp_dir}/wrong-target.out"
  if run_script "${output_file}" \
    EVENT_NAME=workflow_dispatch \
    INPUT_PROFILE=morning-brief-personal \
    INPUT_WORKFLOW_TARGET=shared
  then
    return 1
  fi
}

echo "=== resolve-googleworkspace-feed-matrix.sh tests ==="
echo ""

assert_ok "schedule-selects-shared-profiles" test_schedule_selects_shared_profiles
assert_ok "schedule-selects-personal-profiles" test_schedule_selects_personal_profiles
assert_ok "dispatch-selects-all-personal-profiles" test_dispatch_selects_all_personal_profiles
assert_ok "dispatch-rejects-wrong-workflow-target" test_dispatch_rejects_wrong_workflow_target

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
