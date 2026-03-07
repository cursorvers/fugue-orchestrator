#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
      "enabled_by_default": true,
      "actions": ["standup-report"],
      "reason": ["standup-context"],
      "ttl_minutes": 360
    },
    "morning-brief-personal": {
      "enabled_by_default": true,
      "actions": ["gmail-triage"],
      "reason": ["mail-context"],
      "ttl_minutes": 360
    },
    "weekly-digest-personal": {
      "enabled_by_default": true,
      "actions": ["weekly-digest"],
      "reason": ["digest-context"],
      "ttl_minutes": 10080
    },
    "pre-meeting-scan": {
      "enabled_by_default": false,
      "actions": ["meeting-prep"],
      "reason": ["meeting-context", "document-context"],
      "ttl_minutes": 45
    }
  }
}
EOF

out_root="${tmp_dir}/feeds"
sed -i.bak "s#__OUT_ROOT__#${out_root}#g" "${policy_file}"
rm -f "${policy_file}.bak"

mkdir -p "${out_root}/morning-brief-personal" "${out_root}/morning-brief-shared" "${out_root}/weekly-digest-personal"

cat > "${out_root}/morning-brief-personal/latest.json" <<'EOF'
{
  "profile_id": "morning-brief-personal",
  "status": "ok",
  "summary": "gmail-triage: resultSizeEstimate=8",
  "valid_until": "2026-03-07T12:00:00Z"
}
EOF

cat > "${out_root}/morning-brief-shared/latest.json" <<'EOF'
{
  "profile_id": "morning-brief-shared",
  "status": "skipped",
  "summary": "standup-report: no meetings",
  "valid_until": "2026-03-07T12:00:00Z"
}
EOF

cat > "${out_root}/weekly-digest-personal/latest.json" <<'EOF'
{
  "profile_id": "weekly-digest-personal",
  "status": "ok",
  "summary": "weekly-digest: meetingCount=6, unreadEmails=14",
  "valid_until": "2026-03-14T00:00:00Z"
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

test_selects_enabled_profiles_from_workspace_hints() {
  local output_file="${tmp_dir}/ingest-hints.out"
  local context_file="${tmp_dir}/ingest-hints.json"

  env \
    WORKSPACE_ACTIONS="meeting-prep,gmail-triage" \
    WORKSPACE_REASON="meeting-context,mail-context,document-context" \
    NOW_ISO="2026-03-07T08:00:00Z" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    OUT_ROOT="${out_root}" \
    OUT_FILE="${context_file}" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${INGEST_SCRIPT}" >/dev/null

  grep -q '^feed_ingest_status=ok$' "${output_file}" &&
    grep -q '^feed_requested_profiles=morning-brief-personal$' "${output_file}" &&
    grep -q '^feed_active_profiles=morning-brief-personal$' "${output_file}" &&
    jq -e '.requested_profiles == ["morning-brief-personal"]' "${context_file}" >/dev/null &&
    jq -e '.active_profiles == ["morning-brief-personal"]' "${context_file}" >/dev/null &&
    jq -e '.summary == "morning-brief-personal: gmail-triage: resultSizeEstimate=8"' "${context_file}" >/dev/null
}

test_marks_stale_and_missing_profiles_partial() {
  local output_file="${tmp_dir}/ingest-explicit.out"
  local context_file="${tmp_dir}/ingest-explicit.json"

  env \
    FEED_PROFILES="morning-brief-personal,morning-brief-shared,weekly-digest-personal,missing-profile" \
    NOW_ISO="2026-03-07T13:30:00Z" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    OUT_ROOT="${out_root}" \
    OUT_FILE="${context_file}" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${INGEST_SCRIPT}" >/dev/null

  grep -q '^feed_ingest_status=partial$' "${output_file}" &&
    grep -q '^feed_active_profiles=weekly-digest-personal$' "${output_file}" &&
    jq -e '.active_profiles == ["weekly-digest-personal"]' "${context_file}" >/dev/null &&
    jq -e '.stale_profiles == ["morning-brief-personal","morning-brief-shared"]' "${context_file}" >/dev/null &&
    jq -e '.missing_profiles == ["missing-profile"]' "${context_file}" >/dev/null
}

test_defaults_to_all_enabled_profiles_without_hints() {
  local output_file="${tmp_dir}/ingest-defaults.out"
  local context_file="${tmp_dir}/ingest-defaults.json"

  env \
    NOW_ISO="2026-03-07T08:00:00Z" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    OUT_ROOT="${out_root}" \
    OUT_FILE="${context_file}" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${INGEST_SCRIPT}" >/dev/null

  grep -q '^feed_ingest_status=partial$' "${output_file}" &&
    grep -q '^feed_requested_profiles=morning-brief-shared,morning-brief-personal,weekly-digest-personal$' "${output_file}" &&
    jq -e '.requested_profiles == ["morning-brief-shared","morning-brief-personal","weekly-digest-personal"]' "${context_file}" >/dev/null &&
    jq -e '.active_profiles == ["morning-brief-personal","weekly-digest-personal"]' "${context_file}" >/dev/null &&
    jq -e '.stale_profiles == ["morning-brief-shared"]' "${context_file}" >/dev/null
}

echo "=== googleworkspace feed ingest tests ==="
echo ""

assert_ok "selects-enabled-profiles-from-workspace-hints" test_selects_enabled_profiles_from_workspace_hints
assert_ok "marks-stale-and-missing-profiles-partial" test_marks_stale_and_missing_profiles_partial
assert_ok "defaults-to-all-enabled-profiles-without-hints" test_defaults_to_all_enabled_profiles_without_hints

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
