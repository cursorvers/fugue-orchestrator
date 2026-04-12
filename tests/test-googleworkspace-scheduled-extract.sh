#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRACT_SCRIPT="${SCRIPT_DIR}/scripts/harness/googleworkspace-scheduled-extract.sh"
INGEST_SCRIPT="${SCRIPT_DIR}/scripts/harness/googleworkspace-feed-ingest.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

policy_file="${tmp_dir}/policy.json"
cat > "${policy_file}" <<'EOF'
{
  "version": 1,
  "out_root": "__OUT_ROOT__",
  "profiles": {
    "morning-brief-shared": {
      "title": "Morning shared operator brief",
      "phase": "scheduled-operator-loop",
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "shared",
      "github_environment": "workspace-readonly",
      "schedule_mode": "daily-weekday",
      "recommended_cron_utc": "0 21 * * 0-4",
      "actions": ["standup-report"],
      "domains": ["calendar"],
      "reason": ["standup-context"],
      "ttl_minutes": 60,
      "auth_mode": "service-account-readonly",
      "summary_purpose": "Shared morning digest"
    },
    "morning-brief-personal": {
      "title": "Morning personal mailbox brief",
      "phase": "scheduled-operator-loop",
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "personal",
      "github_environment": "workspace-personal-readonly",
      "schedule_mode": "daily-weekday",
      "recommended_cron_utc": "5 21 * * 0-4",
      "actions": ["gmail-triage"],
      "domains": ["gmail"],
      "reason": ["mail-context"],
      "ttl_minutes": 60,
      "auth_mode": "user-oauth-readonly",
      "summary_purpose": "Personal mailbox digest"
    },
    "weekly-digest-personal": {
      "title": "Weekly personal workspace digest",
      "phase": "scheduled-operator-loop",
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "personal",
      "github_environment": "workspace-personal-readonly",
      "schedule_mode": "weekly",
      "recommended_cron_utc": "15 21 * * 0",
      "actions": ["weekly-digest"],
      "domains": ["calendar", "gmail"],
      "reason": ["digest-context"],
      "ttl_minutes": 10080,
      "auth_mode": "user-oauth-readonly",
      "summary_purpose": "Weekly digest"
    }
  }
}
EOF

out_root="${tmp_dir}/feeds"
sed -i.bak "s#__OUT_ROOT__#${out_root}#g" "${policy_file}"
rm -f "${policy_file}.bak"

fake_preflight="${tmp_dir}/googleworkspace-preflight-enrich.sh"
cat > "${fake_preflight}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${RUN_DIR}/googleworkspace"
printf '%s\t%s\n' "${ISSUE_NUMBER}" "${WORKSPACE_ACTIONS}" >> "${TMP_PREFLIGHT_CALLS_LOG}"
printf '# %s\n\n%s\n' "${ISSUE_TITLE}" "${WORKSPACE_ACTIONS}" > "${REPORT_PATH}"
printf '%s' '{"status":"ok"}' > "${RUN_DIR}/googleworkspace/fake-meta.json"

summary=""
case "${WORKSPACE_ACTIONS}" in
  standup-report)
    summary="standup-report: meetings=2"
    ;;
  gmail-triage)
    summary="gmail-triage: resultSizeEstimate=5"
    ;;
  weekly-digest)
    summary="weekly-digest: meetingCount=6, unreadEmails=14"
    ;;
  *)
    summary="unknown"
    ;;
esac

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "workspace_preflight_status=ok"
    echo "workspace_report_path=${REPORT_PATH}"
    echo "workspace_run_dir=${RUN_DIR}"
    echo "workspace_summary<<EOF"
    echo "${summary}"
    echo "EOF"
  } >> "${GITHUB_OUTPUT}"
fi
EOF
chmod +x "${fake_preflight}"

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

run_extract() {
  local profile="$1"
  local now_iso="$2"
  local output_file="$3"

  env \
    TMP_PREFLIGHT_CALLS_LOG="${tmp_dir}/calls.log" \
    FEED_PROFILE="${profile}" \
    NOW_ISO="${now_iso}" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    PREFLIGHT_SCRIPT="${fake_preflight}" \
    ADAPTER="/bin/true" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${EXTRACT_SCRIPT}" >/dev/null
}

test_generates_feed_manifest_and_latest() {
  local output_file="${tmp_dir}/extract-1.out"
  run_extract "morning-brief-shared" "2026-03-07T00:00:00Z" "${output_file}"

  local latest="${out_root}/morning-brief-shared/latest.json"
  [[ -f "${latest}" ]] &&
    grep -q '^feed_status=ok$' "${output_file}" &&
    grep -q '^feed_cache_hit=false$' "${output_file}" &&
    jq -e '.profile_id == "morning-brief-shared" and .status == "ok" and .valid_until == "2026-03-07T01:00:00Z"' "${latest}" >/dev/null &&
    jq -e '.summary == "standup-report: meetings=2"' "${latest}" >/dev/null
}

test_cache_hit_within_ttl() {
  local output_file="${tmp_dir}/extract-2.out"
  run_extract "morning-brief-shared" "2026-03-07T00:30:00Z" "${output_file}"

  grep -q '^feed_cache_hit=true$' "${output_file}" &&
    [[ "$(wc -l < "${tmp_dir}/calls.log")" -eq 1 ]]
}

test_refreshes_when_stale() {
  local output_file="${tmp_dir}/extract-3.out"
  run_extract "morning-brief-shared" "2026-03-07T01:30:00Z" "${output_file}"

  grep -q '^feed_cache_hit=false$' "${output_file}" &&
    [[ "$(wc -l < "${tmp_dir}/calls.log")" -eq 2 ]]
}

test_accepts_non_executable_preflight_when_invoked_via_bash() {
  local output_file="${tmp_dir}/extract-nonexec.out"

  chmod 0644 "${fake_preflight}"
  run_extract "morning-brief-shared" "2026-03-07T03:00:00Z" "${output_file}"
  chmod +x "${fake_preflight}"

  grep -q '^feed_status=ok$' "${output_file}" &&
    grep -q '^feed_cache_hit=false$' "${output_file}"
}

test_ingests_only_fresh_feeds() {
  local weekly_output="${tmp_dir}/extract-weekly.out"
  local ingest_output="${tmp_dir}/ingest.out"
  local context_file="${tmp_dir}/feed-context.json"

  run_extract "weekly-digest-personal" "2026-03-07T00:00:00Z" "${weekly_output}"

  env \
    FEED_PROFILES="morning-brief-shared,weekly-digest-personal" \
    NOW_ISO="2026-03-07T02:31:00Z" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    OUT_ROOT="${out_root}" \
    OUT_FILE="${context_file}" \
    GITHUB_OUTPUT="${ingest_output}" \
    bash "${INGEST_SCRIPT}" >/dev/null

  grep -q '^feed_ingest_status=partial$' "${ingest_output}" &&
    grep -q '^feed_active_profiles=weekly-digest-personal$' "${ingest_output}" &&
    jq -e '.active_profiles == ["weekly-digest-personal"]' "${context_file}" >/dev/null &&
    jq -e '.stale_profiles == ["morning-brief-shared"]' "${context_file}" >/dev/null &&
    jq -e '.summary | contains("weekly-digest-personal: weekly-digest: meetingCount=6, unreadEmails=14")' "${context_file}" >/dev/null
}

echo "=== googleworkspace scheduled extract tests ==="
echo ""

assert_ok "generates-feed-manifest-and-latest" test_generates_feed_manifest_and_latest
assert_ok "cache-hit-within-ttl" test_cache_hit_within_ttl
assert_ok "refreshes-when-stale" test_refreshes_when_stale
assert_ok "ingests-only-fresh-feeds" test_ingests_only_fresh_feeds
assert_ok "accepts-non-executable-preflight-when-invoked-via-bash" test_accepts_non_executable_preflight_when_invoked_via_bash

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
