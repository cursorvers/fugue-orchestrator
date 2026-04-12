#!/usr/bin/env bash
set -euo pipefail

FEED_PROFILE="${FEED_PROFILE:-}"
POLICY_FILE="${GOOGLEWORKSPACE_FEED_POLICY_FILE:-config/integrations/googleworkspace-feed-policy.json}"
PREFLIGHT_SCRIPT="${PREFLIGHT_SCRIPT:-scripts/harness/googleworkspace-preflight-enrich.sh}"
ADAPTER="${ADAPTER:-scripts/lib/googleworkspace-cli-adapter.sh}"
OUT_ROOT="${OUT_ROOT:-}"
FORCE_REFRESH="${FORCE_REFRESH:-false}"
NOW_ISO="${NOW_ISO:-}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

is_manifest_fresh() {
  local manifest_path="$1"
  local now_iso="$2"
  jq -e --arg now "${now_iso}" '
    (.valid_until // "" | select(length > 0) | fromdateiso8601) >= ($now | fromdateiso8601)
  ' "${manifest_path}" >/dev/null 2>&1
}

extract_multiline_output() {
  local output_path="$1"
  local key="$2"
  awk -v needle="${key}" '
    $0 == needle "<<EOF" { capture = 1; next }
    capture && $0 == "EOF" { capture = 0; exit }
    capture { print }
  ' "${output_path}"
}

read_output_value() {
  local output_path="$1"
  local key="$2"
  local line
  line="$(grep -E "^${key}=" "${output_path}" | tail -n 1 || true)"
  printf '%s' "${line#*=}"
}

require_cmd jq
[[ -n "${FEED_PROFILE}" ]] || fail "FEED_PROFILE is required"
[[ -f "${POLICY_FILE}" ]] || fail "policy file not found: ${POLICY_FILE}"
[[ -f "${PREFLIGHT_SCRIPT}" ]] || fail "preflight script missing: ${PREFLIGHT_SCRIPT}"

profile_json="$(jq -cer --arg profile "${FEED_PROFILE}" '.profiles[$profile]' "${POLICY_FILE}")" \
  || fail "profile not found in policy: ${FEED_PROFILE}"

if [[ -z "${NOW_ISO}" ]]; then
  NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

if [[ -z "${OUT_ROOT}" ]]; then
  OUT_ROOT="$(jq -r '.out_root // ".fugue/feeds/googleworkspace"' "${POLICY_FILE}")"
fi

FORCE_REFRESH="$(normalize_bool "${FORCE_REFRESH}")"

title="$(printf '%s' "${profile_json}" | jq -r '.title')"
phase="$(printf '%s' "${profile_json}" | jq -r '.phase')"
auth_mode="$(printf '%s' "${profile_json}" | jq -r '.auth_mode')"
ttl_minutes="$(printf '%s' "${profile_json}" | jq -r '.ttl_minutes')"
summary_purpose="$(printf '%s' "${profile_json}" | jq -r '.summary_purpose // ""')"
schedule_mode="$(printf '%s' "${profile_json}" | jq -r '.schedule_mode // ""')"
recommended_cron_utc="$(printf '%s' "${profile_json}" | jq -r '.recommended_cron_utc // ""')"
actions_csv="$(printf '%s' "${profile_json}" | jq -r '.actions | join(",")')"
domains_csv="$(printf '%s' "${profile_json}" | jq -r '.domains | join(",")')"
reason_csv="$(printf '%s' "${profile_json}" | jq -r '.reason | join(",")')"

[[ "${ttl_minutes}" =~ ^[0-9]+$ ]] || fail "ttl_minutes must be numeric for profile ${FEED_PROFILE}"

profile_dir="${OUT_ROOT%/}/${FEED_PROFILE}"
latest_manifest_path="${profile_dir}/latest.json"
mkdir -p "${profile_dir}"

if [[ "${FORCE_REFRESH}" != "true" && -f "${latest_manifest_path}" ]] && is_manifest_fresh "${latest_manifest_path}" "${NOW_ISO}"; then
  feed_status="$(jq -r '.status // "ok"' "${latest_manifest_path}")"
  feed_summary="$(jq -r '.summary // ""' "${latest_manifest_path}")"
  feed_manifest_path="${latest_manifest_path}"
  feed_cache_hit="true"
  feed_valid_until="$(jq -r '.valid_until // ""' "${latest_manifest_path}")"
else
  snapshot_id="$(printf '%s' "${NOW_ISO}" | sed -E 's/[-:]//g; s/T/-/; s/Z$//')"
  snapshot_dir="${profile_dir}/${snapshot_id}"
  run_dir="${snapshot_dir}/googleworkspace-run"
  report_path="${snapshot_dir}/googleworkspace-report.md"
  output_path="$(mktemp)"

  mkdir -p "${snapshot_dir}"

  service_credentials_file=""
  service_credentials_json=""
  user_credentials_file=""
  user_credentials_json=""

  case "${auth_mode}" in
    service-account-readonly)
      service_credentials_file="${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}"
      service_credentials_json="${GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON:-}"
      ;;
    user-oauth-readonly)
      user_credentials_file="${GOOGLE_WORKSPACE_USER_CREDENTIALS_FILE:-}"
      user_credentials_json="${GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON:-}"
      ;;
    *)
      service_credentials_file="${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}"
      service_credentials_json="${GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON:-}"
      user_credentials_file="${GOOGLE_WORKSPACE_USER_CREDENTIALS_FILE:-}"
      user_credentials_json="${GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON:-}"
      ;;
  esac

  env \
    ISSUE_NUMBER="feed-${FEED_PROFILE}" \
    ISSUE_TITLE="${title}" \
    ISSUE_BODY="${summary_purpose}" \
    WORKSPACE_ACTIONS="${actions_csv}" \
    WORKSPACE_DOMAINS="${domains_csv}" \
    WORKSPACE_REASON="${reason_csv}" \
    WORKSPACE_SUGGESTED_PHASES="${phase}" \
    OUT_DIR="${snapshot_dir}" \
    RUN_DIR="${run_dir}" \
    REPORT_PATH="${report_path}" \
    ADAPTER="${ADAPTER}" \
    GITHUB_OUTPUT="${output_path}" \
    GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="${service_credentials_file}" \
    GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON="${service_credentials_json}" \
    GOOGLE_WORKSPACE_USER_CREDENTIALS_FILE="${user_credentials_file}" \
    GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON="${user_credentials_json}" \
    bash "${PREFLIGHT_SCRIPT}"

  feed_status="$(read_output_value "${output_path}" "workspace_preflight_status")"
  feed_summary="$(extract_multiline_output "${output_path}" "workspace_summary" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g')"
  feed_manifest_path="${snapshot_dir}/feed.json"
  feed_cache_hit="false"
  feed_valid_until="$(jq -nr --arg now "${NOW_ISO}" --argjson ttl "${ttl_minutes}" '($now | fromdateiso8601) + ($ttl * 60) | todateiso8601')"

  jq -cn \
    --arg profile_id "${FEED_PROFILE}" \
    --arg title "${title}" \
    --arg phase "${phase}" \
    --arg auth_mode "${auth_mode}" \
    --arg schedule_mode "${schedule_mode}" \
    --arg recommended_cron_utc "${recommended_cron_utc}" \
    --arg generated_at "${NOW_ISO}" \
    --arg valid_until "${feed_valid_until}" \
    --arg status "${feed_status}" \
    --arg summary "${feed_summary}" \
    --arg report_path "${report_path}" \
    --arg run_dir "${run_dir}" \
    --arg summary_purpose "${summary_purpose}" \
    --argjson ttl_minutes "${ttl_minutes}" \
    --argjson actions "$(printf '%s' "${profile_json}" | jq -c '.actions')" \
    --argjson domains "$(printf '%s' "${profile_json}" | jq -c '.domains')" \
    --argjson reason "$(printf '%s' "${profile_json}" | jq -c '.reason')" \
    '{
      version: 1,
      profile_id: $profile_id,
      title: $title,
      phase: $phase,
      auth_mode: $auth_mode,
      schedule_mode: $schedule_mode,
      recommended_cron_utc: $recommended_cron_utc,
      generated_at: $generated_at,
      valid_until: $valid_until,
      ttl_minutes: $ttl_minutes,
      status: $status,
      summary: $summary,
      actions: $actions,
      domains: $domains,
      reason: $reason,
      summary_purpose: $summary_purpose,
      report_path: $report_path,
      raw_run_dir: $run_dir,
      cache_hit: false
    }' > "${feed_manifest_path}"

  cp "${feed_manifest_path}" "${latest_manifest_path}"
  rm -f "${output_path}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "feed_profile=${FEED_PROFILE}"
    echo "feed_status=${feed_status}"
    echo "feed_cache_hit=${feed_cache_hit}"
    echo "feed_manifest_path=${feed_manifest_path}"
    echo "feed_latest_manifest_path=${latest_manifest_path}"
    echo "feed_valid_until=${feed_valid_until}"
    echo "feed_summary<<EOF"
    echo "${feed_summary}"
    echo "EOF"
  } >> "${GITHUB_OUTPUT}"
fi

printf 'feed_profile=%s\n' "${FEED_PROFILE}"
printf 'feed_status=%s\n' "${feed_status}"
printf 'feed_cache_hit=%s\n' "${feed_cache_hit}"
printf 'feed_manifest_path=%s\n' "${feed_manifest_path}"
