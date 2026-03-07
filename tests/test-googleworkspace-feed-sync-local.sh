#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_SCRIPT="${SCRIPT_DIR}/scripts/local/googleworkspace-feed-sync-local.sh"

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
      "execution_target": "github-actions",
      "workflow_target": "shared"
    },
    "morning-brief-personal": {
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "personal"
    },
    "weekly-digest-personal": {
      "enabled_by_default": true,
      "execution_target": "github-actions",
      "workflow_target": "personal"
    }
  }
}
EOF

out_root="${tmp_dir}/feeds"
sed -i.bak "s#__OUT_ROOT__#${out_root}#g" "${policy_file}"
rm -f "${policy_file}.bak"

fake_extract="${tmp_dir}/extract.sh"
cat > "${fake_extract}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${OUT_ROOT}/${FEED_PROFILE}"
printf '%s\n' "${FEED_PROFILE}" >> "${TMP_LOCAL_CALLS_LOG}"
cat > "${OUT_ROOT}/${FEED_PROFILE}/latest.json" <<JSON
{"profile_id":"${FEED_PROFILE}","valid_until":"2099-01-01T00:00:00Z","status":"ok","summary":"${FEED_PROFILE} summary"}
JSON
EOF
chmod +x "${fake_extract}"

fake_ingest="${tmp_dir}/ingest.sh"
cat > "${fake_ingest}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${FEED_PROFILES}" > "${TMP_INGEST_PROFILES_LOG}"
printf '%s\n' "${OUT_FILE}" > "${TMP_INGEST_OUT_FILE_LOG}"
printf '{"status":"ok"}\n' > "${OUT_FILE}"
EOF
chmod +x "${fake_ingest}"

fake_gws_dir="${tmp_dir}/bin"
mkdir -p "${fake_gws_dir}"
cat > "${fake_gws_dir}/gws" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${fake_gws_dir}/gws"

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

test_defaults_to_personal_fallback_profiles_only() {
  local calls_log="${tmp_dir}/local-calls.log"
  local ingest_profiles_log="${tmp_dir}/ingest-profiles.log"
  local ingest_out_file_log="${tmp_dir}/ingest-out-file.log"

  env \
    PATH="${fake_gws_dir}:${PATH}" \
    TMP_LOCAL_CALLS_LOG="${calls_log}" \
    TMP_INGEST_PROFILES_LOG="${ingest_profiles_log}" \
    TMP_INGEST_OUT_FILE_LOG="${ingest_out_file_log}" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${policy_file}" \
    GOOGLEWORKSPACE_SCHEDULED_EXTRACT_SCRIPT="${fake_extract}" \
    GOOGLEWORKSPACE_FEED_INGEST_SCRIPT="${fake_ingest}" \
    OUT_ROOT="${out_root}" \
    bash "${LOCAL_SCRIPT}" >/dev/null

  grep -q '^morning-brief-personal$' "${calls_log}" &&
    grep -q '^weekly-digest-personal$' "${calls_log}" &&
    ! grep -q 'morning-brief-shared' "${calls_log}" &&
    grep -q '^morning-brief-personal,weekly-digest-personal$' "${ingest_profiles_log}" &&
    grep -q 'googleworkspace-feed-context.local.json' "${ingest_out_file_log}"
}

echo "=== googleworkspace feed local sync tests ==="
echo ""

assert_ok "defaults-to-personal-fallback-profiles-only" test_defaults_to_personal_fallback_profiles_only

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
