#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARED_SECRETS_LOADER="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"
ORG="cursorvers"
REPO="cursorvers/fugue-orchestrator"
ENV_FILE=""
APPLY="false"
ENV_FILE_EXPLICIT="false"

required_missing=0
set_ok=0
set_fail=0
set_skip=0

usage() {
  cat <<'EOF'
Usage: scripts/local/sync-gh-secrets-from-env.sh [options]

Options:
  --env-file <path>   Load env vars from an explicit external env file
  --org <name>        GitHub organization (default: cursorvers)
  --repo <owner/repo> Target repository (default: cursorvers/fugue-orchestrator)
  --apply             Apply changes (default: dry-run)
  --dry-run           Print planned updates only
  -h, --help          Show help

Notes:
  - Default mode is dry-run.
  - In apply mode, org secrets are set with visibility=selected and merged with the
    current selected repo set for that secret.
  - TARGET_REPO_PAT is set as a repository secret.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      ENV_FILE_EXPLICIT="true"
      shift 2
      ;;
    --org)
      ORG="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --dry-run)
      APPLY="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found." >&2
  exit 1
fi

if [[ "${ENV_FILE_EXPLICIT}" == "true" ]]; then
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: env file not found: ${ENV_FILE}" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  set -a
  source "${ENV_FILE}"
  set +a
elif [[ -n "${ENV_FILE}" ]]; then
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: env file not found: ${ENV_FILE}" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  set -a
  source "${ENV_FILE}"
  set +a
else
  echo "Info: no env file specified; using current process environment only."
fi

if [[ -n "${ENV_FILE}" ]]; then
  export SHARED_SECRETS_ENV_FILE="${ENV_FILE}"
fi

if [[ -f "${SHARED_SECRETS_LOADER}" ]]; then
  eval "$(
    bash "${SHARED_SECRETS_LOADER}" export \
      OPENAI_API_KEY \
      ZAI_API_KEY \
      ANTHROPIC_API_KEY \
      GEMINI_API_KEY \
      XAI_API_KEY \
      TARGET_REPO_PAT \
      FUGUE_OPS_PAT
  )"
fi

normalize_repo_csv() {
  printf '%s' "${1}" | tr ',' '\n' | awk 'NF {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if (!seen[$0]++) print $0}'
}

current_org_secret_repo_csv() {
  local secret_name="$1"
  gh api "orgs/${ORG}/actions/secrets/${secret_name}/repositories" --paginate --jq '.repositories[].full_name' 2>/dev/null \
    | awk 'NF && !seen[$0]++ { out = out ? out "," $0 : $0 } END { print out }'
}

current_org_variable_repo_csv() {
  local variable_name="$1"
  gh api "orgs/${ORG}/actions/variables/${variable_name}/repositories" --paginate --jq '.repositories[].full_name' 2>/dev/null \
    | awk 'NF && !seen[$0]++ { out = out ? out "," $0 : $0 } END { print out }'
}

merge_repo_csv() {
  local left="$1"
  local right="$2"
  { normalize_repo_csv "${left}"; normalize_repo_csv "${right}"; } \
    | awk 'NF && !seen[$0]++ { out = out ? out "," $0 : $0 } END { print out }'
}

if [[ "${APPLY}" == "true" ]]; then
  if ! gh auth status -h github.com >/dev/null 2>&1; then
    echo "Error: gh auth is not ready. Run: gh auth login -h github.com" >&2
    exit 1
  fi
fi

RESOLVED_SOURCE=""
RESOLVED_VALUE=""
resolve_first_nonempty() {
  RESOLVED_SOURCE=""
  RESOLVED_VALUE=""
  local name=""
  local value=""
  for name in "$@"; do
    value="${!name-}"
    if [[ -n "${value}" ]]; then
      RESOLVED_SOURCE="${name}"
      RESOLVED_VALUE="${value}"
      return 0
    fi
  done
  return 1
}

apply_secret() {
  local scope="$1"
  local secret_name="$2"
  local required="$3"
  shift 3
  local candidates=("$@")

  if ! resolve_first_nonempty "${candidates[@]}"; then
    if [[ "${required}" == "required" ]]; then
      echo "MISSING(required): ${secret_name} (candidates: ${candidates[*]})"
      required_missing=$((required_missing + 1))
    else
      echo "SKIP(optional): ${secret_name} (no value in: ${candidates[*]})"
      set_skip=$((set_skip + 1))
    fi
    return 0
  fi

  if [[ "${APPLY}" != "true" ]]; then
    echo "DRY-RUN: set ${scope} secret ${secret_name} from ${RESOLVED_SOURCE}"
    set_ok=$((set_ok + 1))
    return 0
  fi

  if [[ "${scope}" == "org" ]]; then
    local existing_repo_csv merged_repo_csv
    existing_repo_csv="$(current_org_secret_repo_csv "${secret_name}")"
    merged_repo_csv="$(merge_repo_csv "${existing_repo_csv}" "${REPO}")"
    if printf '%s' "${RESOLVED_VALUE}" | gh secret set "${secret_name}" --org "${ORG}" --visibility selected --repos "${merged_repo_csv}" >/dev/null; then
      echo "OK: set org secret ${secret_name} from ${RESOLVED_SOURCE} (repos=${merged_repo_csv})"
      set_ok=$((set_ok + 1))
    else
      echo "FAIL: org secret ${secret_name}" >&2
      set_fail=$((set_fail + 1))
    fi
  else
    if printf '%s' "${RESOLVED_VALUE}" | gh secret set "${secret_name}" --repo "${REPO}" >/dev/null; then
      echo "OK: set repo secret ${secret_name} from ${RESOLVED_SOURCE}"
      set_ok=$((set_ok + 1))
    else
      echo "FAIL: repo secret ${secret_name}" >&2
      set_fail=$((set_fail + 1))
    fi
  fi
}

apply_variable() {
  local scope="$1"
  local variable_name="$2"
  local required="$3"
  shift 3
  local candidates=("$@")

  if ! resolve_first_nonempty "${candidates[@]}"; then
    if [[ "${required}" == "required" ]]; then
      echo "MISSING(required): ${variable_name} (candidates: ${candidates[*]})"
      required_missing=$((required_missing + 1))
    else
      echo "SKIP(optional): ${variable_name} (no value in: ${candidates[*]})"
      set_skip=$((set_skip + 1))
    fi
    return 0
  fi

  if [[ "${APPLY}" != "true" ]]; then
    echo "DRY-RUN: set ${scope} variable ${variable_name} from ${RESOLVED_SOURCE}"
    set_ok=$((set_ok + 1))
    return 0
  fi

  if [[ "${scope}" == "org" ]]; then
    local existing_repo_csv merged_repo_csv
    existing_repo_csv="$(current_org_variable_repo_csv "${variable_name}")"
    merged_repo_csv="$(merge_repo_csv "${existing_repo_csv}" "${REPO}")"
    if printf '%s' "${RESOLVED_VALUE}" | gh variable set "${variable_name}" --org "${ORG}" --visibility selected --repos "${merged_repo_csv}" >/dev/null; then
      echo "OK: set org variable ${variable_name} from ${RESOLVED_SOURCE} (repos=${merged_repo_csv})"
      set_ok=$((set_ok + 1))
    else
      echo "FAIL: org variable ${variable_name}" >&2
      set_fail=$((set_fail + 1))
    fi
  else
    if printf '%s' "${RESOLVED_VALUE}" | gh variable set "${variable_name}" --repo "${REPO}" >/dev/null; then
      echo "OK: set repo variable ${variable_name} from ${RESOLVED_SOURCE}"
      set_ok=$((set_ok + 1))
    else
      echo "FAIL: repo variable ${variable_name}" >&2
      set_fail=$((set_fail + 1))
    fi
  fi
}

env_source="process-env"
if [[ -n "${ENV_FILE}" ]]; then
  env_source="${ENV_FILE}"
fi
echo "mode=$([[ "${APPLY}" == "true" ]] && echo apply || echo dry-run) org=${ORG} repo=${REPO} env=${env_source}"

# Core shared secrets. Audit decides what is truly required per repo.
apply_secret org OPENAI_API_KEY optional OPENAI_API_KEY
apply_secret org ZAI_API_KEY optional ZAI_API_KEY
apply_secret repo TARGET_REPO_PAT optional TARGET_REPO_PAT

# Optional providers
apply_secret org ANTHROPIC_API_KEY optional ANTHROPIC_API_KEY
apply_secret org GEMINI_API_KEY optional GEMINI_API_KEY
apply_secret org XAI_API_KEY optional XAI_API_KEY XAI_API

# Ops and notification lifelines
apply_secret org FUGUE_OPS_PAT optional FUGUE_OPS_PAT
apply_secret org DISCORD_ADMIN_WEBHOOK_URL optional DISCORD_ADMIN_WEBHOOK_URL
apply_secret org DISCORD_WEBHOOK_URL optional DISCORD_WEBHOOK_URL
apply_secret org DISCORD_SYSTEM_WEBHOOK optional DISCORD_SYSTEM_WEBHOOK
apply_secret org N8N_API_KEY optional N8N_API_KEY
apply_variable org N8N_INSTANCE_URL optional N8N_INSTANCE_URL
apply_secret org SUPABASE_ACCESS_TOKEN optional SUPABASE_ACCESS_TOKEN
apply_variable org SUPABASE_PROJECT_ID optional SUPABASE_PROJECT_ID
apply_secret org SUPABASE_URL optional SUPABASE_URL
apply_secret org GOOGLE_SERVICE_ACCOUNT_JSON optional GOOGLE_SERVICE_ACCOUNT_JSON
apply_secret org PROGRESS_WEBHOOK_URL optional PROGRESS_WEBHOOK_URL

apply_secret org LINE_WEBHOOK_URL optional LINE_WEBHOOK_URL
apply_secret org LINE_CHANNEL_ACCESS_TOKEN optional LINE_CHANNEL_ACCESS_TOKEN
apply_secret org LINE_TO optional LINE_TO
apply_secret org LINE_NOTIFY_TOKEN optional LINE_NOTIFY_TOKEN LINE_NOTIFY_ACCESS_TOKEN
apply_secret org LINE_NOTIFY_ACCESS_TOKEN optional LINE_NOTIFY_ACCESS_TOKEN LINE_NOTIFY_TOKEN

echo ""
echo "summary: ok=${set_ok} skipped=${set_skip} missing_required=${required_missing} failed=${set_fail}"

if (( required_missing > 0 )); then
  exit 2
fi
if (( set_fail > 0 )); then
  exit 3
fi

exit 0
