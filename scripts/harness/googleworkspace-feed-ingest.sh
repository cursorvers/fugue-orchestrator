#!/usr/bin/env bash
set -euo pipefail

FEED_PROFILES="${FEED_PROFILES:-}"
POLICY_FILE="${GOOGLEWORKSPACE_FEED_POLICY_FILE:-config/integrations/googleworkspace-feed-policy.json}"
OUT_ROOT="${OUT_ROOT:-}"
NOW_ISO="${NOW_ISO:-}"
OUT_FILE="${OUT_FILE:-}"
WORKSPACE_ACTIONS="${WORKSPACE_ACTIONS:-}"
WORKSPACE_REASON="${WORKSPACE_REASON:-}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

csv_to_json_array() {
  jq -cn --arg csv "${1}" '$csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))'
}

require_cmd jq
[[ -f "${POLICY_FILE}" ]] || fail "policy file not found: ${POLICY_FILE}"

if [[ -z "${NOW_ISO}" ]]; then
  NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

if [[ -z "${OUT_ROOT}" ]]; then
  OUT_ROOT="$(jq -r '.out_root // ".fugue/feeds/googleworkspace"' "${POLICY_FILE}")"
fi

if [[ -z "${OUT_FILE}" ]]; then
  OUT_FILE="${OUT_ROOT%/}/googleworkspace-feed-context.json"
fi

if [[ -n "${FEED_PROFILES}" ]]; then
  requested_profiles_json="$(csv_to_json_array "${FEED_PROFILES}")"
elif [[ -n "${WORKSPACE_ACTIONS}" || -n "${WORKSPACE_REASON}" ]]; then
  requested_profiles_json="$(jq -c \
    --arg actions_csv "${WORKSPACE_ACTIONS}" \
    --arg reason_csv "${WORKSPACE_REASON}" '
    ($actions_csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))) as $actions
    | ($reason_csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))) as $reasons
    | [
        .profiles
        | to_entries[]
        | select(.value.enabled_by_default == true)
        | select(
            ([ (.value.actions // [])[] as $profile_action | select($actions | index($profile_action) != null) ] | length) > 0
            or ([ (.value.reason // [])[] as $profile_reason | select($reasons | index($profile_reason) != null) ] | length) > 0
          )
        | .key
      ]' "${POLICY_FILE}")"
else
  requested_profiles_json="$(jq -c '[.profiles | to_entries[] | select(.value.enabled_by_default == true) | .key]' "${POLICY_FILE}")"
fi

mkdir -p "$(dirname "${OUT_FILE}")"

active_entries="[]"
stale_profiles="[]"
missing_profiles="[]"

while IFS= read -r profile_id; do
  [[ -n "${profile_id}" ]] || continue
  manifest_path="${OUT_ROOT%/}/${profile_id}/latest.json"
  if [[ ! -f "${manifest_path}" ]]; then
    missing_profiles="$(jq -cn --argjson current "${missing_profiles}" --arg id "${profile_id}" '$current + [$id]')"
    continue
  fi

  is_fresh="$(jq -r --arg now "${NOW_ISO}" '((.valid_until // "" | select(length > 0) | fromdateiso8601) >= ($now | fromdateiso8601)) // false' "${manifest_path}" 2>/dev/null || echo "false")"
  if [[ "${is_fresh}" != "true" ]]; then
    stale_profiles="$(jq -cn --argjson current "${stale_profiles}" --arg id "${profile_id}" '$current + [$id]')"
    continue
  fi

  status="$(jq -r '.status // "unknown"' "${manifest_path}")"
  if [[ "${status}" == "skipped" ]]; then
    stale_profiles="$(jq -cn --argjson current "${stale_profiles}" --arg id "${profile_id}" '$current + [$id]')"
    continue
  fi

  active_entries="$(jq -cn \
    --argjson current "${active_entries}" \
    --slurpfile entry "${manifest_path}" \
    '$current + [$entry[0]]')"
done < <(printf '%s\n' "${requested_profiles_json}" | jq -r '.[]')

combined_summary="$(printf '%s' "${active_entries}" | jq -r '[.[] | "\(.profile_id): \(.summary)"] | join(" | ")')"
active_profiles="$(printf '%s' "${active_entries}" | jq -c '[.[] | .profile_id]')"

status="ok"
if [[ "$(printf '%s' "${active_entries}" | jq 'length')" -eq 0 ]]; then
  status="skipped"
  combined_summary="No fresh Google Workspace feeds were available."
elif [[ "$(printf '%s' "${stale_profiles}" | jq 'length')" -gt 0 || "$(printf '%s' "${missing_profiles}" | jq 'length')" -gt 0 ]]; then
  status="partial"
fi

jq -cn \
  --arg generated_at "${NOW_ISO}" \
  --arg out_root "${OUT_ROOT}" \
  --arg status "${status}" \
  --arg summary "${combined_summary}" \
  --argjson requested_profiles "${requested_profiles_json}" \
  --argjson active_profiles "${active_profiles}" \
  --argjson stale_profiles "${stale_profiles}" \
  --argjson missing_profiles "${missing_profiles}" \
  --argjson entries "${active_entries}" '
  {
    version: 1,
    generated_at: $generated_at,
    out_root: $out_root,
    status: $status,
    summary: $summary,
    requested_profiles: $requested_profiles,
    active_profiles: $active_profiles,
    stale_profiles: $stale_profiles,
    missing_profiles: $missing_profiles,
    entries: $entries
  }' > "${OUT_FILE}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "feed_ingest_status=${status}"
    echo "feed_context_file=${OUT_FILE}"
    echo "feed_requested_profiles=$(printf '%s' "${requested_profiles_json}" | jq -r 'join(",")')"
    echo "feed_summary<<EOF"
    echo "${combined_summary}"
    echo "EOF"
    echo "feed_active_profiles=$(printf '%s' "${active_profiles}" | jq -r 'join(",")')"
  } >> "${GITHUB_OUTPUT}"
fi

printf 'feed_ingest_status=%s\n' "${status}"
printf 'feed_context_file=%s\n' "${OUT_FILE}"
