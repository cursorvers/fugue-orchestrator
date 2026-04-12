#!/usr/bin/env bash
set -euo pipefail

POLICY_FILE="${GOOGLEWORKSPACE_FEED_POLICY_FILE:-config/integrations/googleworkspace-feed-policy.json}"
EXTRACT_SCRIPT="${GOOGLEWORKSPACE_SCHEDULED_EXTRACT_SCRIPT:-scripts/harness/googleworkspace-scheduled-extract.sh}"
INGEST_SCRIPT="${GOOGLEWORKSPACE_FEED_INGEST_SCRIPT:-scripts/harness/googleworkspace-feed-ingest.sh}"
OUT_ROOT="${OUT_ROOT:-.fugue/feeds/googleworkspace}"
PROFILE_CSV=""
FORCE_REFRESH="${FORCE_REFRESH:-false}"
NOW_ISO="${NOW_ISO:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/googleworkspace-feed-sync-local.sh [options]

Fallback operator-only runner. The primary scheduled path is GitHub Actions.

Options:
  --profile <id|csv>     One or more operator-fallback feed profiles to sync.
  --all                  Sync all enabled operator-fallback profiles (default).
  --out-root <path>      Output root (default: .fugue/feeds/googleworkspace)
  --force-refresh        Ignore TTL cache and refresh manifests.
  --now-iso <timestamp>  Override current UTC timestamp for simulation.
  -h, --help             Show help.
EOF
}

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE_CSV="${2:-}"
      shift 2
      ;;
    --all)
      PROFILE_CSV=""
      shift
      ;;
    --out-root)
      OUT_ROOT="${2:-}"
      shift 2
      ;;
    --force-refresh)
      FORCE_REFRESH="true"
      shift
      ;;
    --now-iso)
      NOW_ISO="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

require_cmd jq
require_cmd bash
require_cmd gws
[[ -f "${POLICY_FILE}" ]] || fail "policy file not found: ${POLICY_FILE}"
[[ -x "${EXTRACT_SCRIPT}" ]] || fail "extract script missing or not executable: ${EXTRACT_SCRIPT}"
[[ -x "${INGEST_SCRIPT}" ]] || fail "ingest script missing or not executable: ${INGEST_SCRIPT}"

FORCE_REFRESH="$(normalize_bool "${FORCE_REFRESH}")"

if [[ -z "${NOW_ISO}" ]]; then
  NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

if [[ -z "${PROFILE_CSV}" ]]; then
  profiles_json="$(jq -c '[.profiles | to_entries[] | select(.value.enabled_by_default == true) | select((.value.execution_target == "local-only") or (.value.workflow_target == "personal")) | .key]' "${POLICY_FILE}")"
else
  profiles_json="$(jq -cn --arg csv "${PROFILE_CSV}" '$csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))')"
fi

profiles_csv="$(printf '%s' "${profiles_json}" | jq -r 'join(",")')"
[[ -n "${profiles_csv}" ]] || fail "no local feed profiles resolved"

mkdir -p "${OUT_ROOT}"

while IFS= read -r profile; do
  [[ -n "${profile}" ]] || continue
  execution_target="$(jq -r --arg profile "${profile}" '.profiles[$profile].execution_target // ""' "${POLICY_FILE}")"
  workflow_target="$(jq -r --arg profile "${profile}" '.profiles[$profile].workflow_target // ""' "${POLICY_FILE}")"
  if [[ "${execution_target}" != "local-only" && "${workflow_target}" != "personal" ]]; then
    fail "profile ${profile} is not available for local fallback"
  fi

  env \
    FEED_PROFILE="${profile}" \
    FORCE_REFRESH="${FORCE_REFRESH}" \
    NOW_ISO="${NOW_ISO}" \
    GOOGLEWORKSPACE_FEED_POLICY_FILE="${POLICY_FILE}" \
    OUT_ROOT="${OUT_ROOT}" \
    bash "${EXTRACT_SCRIPT}"
done < <(printf '%s\n' "${profiles_json}" | jq -r '.[]')

context_file="${OUT_ROOT%/}/googleworkspace-feed-context.local.json"
env \
  FEED_PROFILES="${profiles_csv}" \
  NOW_ISO="${NOW_ISO}" \
  GOOGLEWORKSPACE_FEED_POLICY_FILE="${POLICY_FILE}" \
  OUT_ROOT="${OUT_ROOT}" \
  OUT_FILE="${context_file}" \
  bash "${INGEST_SCRIPT}"

printf 'local_feed_profiles=%s\n' "${profiles_csv}"
printf 'local_feed_context=%s\n' "${context_file}"
