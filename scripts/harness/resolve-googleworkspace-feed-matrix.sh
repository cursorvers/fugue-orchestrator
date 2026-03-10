#!/usr/bin/env bash
set -euo pipefail

POLICY_FILE="${GOOGLEWORKSPACE_FEED_POLICY_FILE:-config/integrations/googleworkspace-feed-policy.json}"
EVENT_NAME="${EVENT_NAME:-workflow_dispatch}"
SCHEDULE_EXPR="${SCHEDULE_EXPR:-}"
INPUT_PROFILE="${INPUT_PROFILE:-}"
INPUT_WORKFLOW_TARGET="${INPUT_WORKFLOW_TARGET:-}"
INPUT_FORCE_REFRESH="${INPUT_FORCE_REFRESH:-false}"

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

require_cmd jq
[[ -f "${POLICY_FILE}" ]] || fail "policy file not found: ${POLICY_FILE}"
[[ -n "${INPUT_WORKFLOW_TARGET}" ]] || fail "INPUT_WORKFLOW_TARGET is required"

force_refresh="false"

if [[ "${EVENT_NAME}" == "schedule" ]]; then
  [[ -n "${SCHEDULE_EXPR}" ]] || fail "SCHEDULE_EXPR is required for scheduled resolution"
  matrix="$(jq -c \
    --arg schedule "${SCHEDULE_EXPR}" \
    --arg workflow_target "${INPUT_WORKFLOW_TARGET}" '
    [
      .profiles
      | to_entries[]
      | select(.value.execution_target == "github-actions")
      | select(.value.workflow_target == $workflow_target)
      | select(.value.enabled_by_default == true)
      | select(.value.recommended_cron_utc == $schedule)
      | {
          profile: .key,
          environment: (.value.github_environment // "")
        }
      | select(.environment | length > 0)
    ]' "${POLICY_FILE}")"
else
  profile="${INPUT_PROFILE:-all}"
  case "${profile}" in
    ""|"all"|"all-${INPUT_WORKFLOW_TARGET}")
      matrix="$(jq -c \
        --arg workflow_target "${INPUT_WORKFLOW_TARGET}" '
        [
          .profiles
          | to_entries[]
          | select(.value.execution_target == "github-actions")
          | select(.value.workflow_target == $workflow_target)
          | {
              profile: .key,
              environment: (.value.github_environment // "")
            }
          | select(.environment | length > 0)
        ]' "${POLICY_FILE}")"
      ;;
    *)
      profile_target="$(jq -r --arg profile "${profile}" '.profiles[$profile].workflow_target // ""' "${POLICY_FILE}")"
      execution_target="$(jq -r --arg profile "${profile}" '.profiles[$profile].execution_target // ""' "${POLICY_FILE}")"
      if [[ "${execution_target}" != "github-actions" ]]; then
        fail "profile ${profile} is not available in GitHub Actions feed sync"
      fi
      if [[ "${profile_target}" != "${INPUT_WORKFLOW_TARGET}" ]]; then
        fail "profile ${profile} does not belong to workflow target ${INPUT_WORKFLOW_TARGET}"
      fi
      matrix="$(jq -c \
        --arg profile "${profile}" '
        [
          {
            profile: $profile,
            environment: (.profiles[$profile].github_environment // "")
          }
          | select(.environment | length > 0)
        ]' "${POLICY_FILE}")"
      ;;
  esac
  force_refresh="$(normalize_bool "${INPUT_FORCE_REFRESH}")"
fi

profile_count="$(printf '%s' "${matrix}" | jq 'length')"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "matrix=${matrix}"
    echo "force_refresh=${force_refresh}"
    echo "profile_count=${profile_count}"
  } >> "${GITHUB_OUTPUT}"
fi

printf 'matrix=%s\n' "${matrix}"
printf 'force_refresh=%s\n' "${force_refresh}"
printf 'profile_count=%s\n' "${profile_count}"
