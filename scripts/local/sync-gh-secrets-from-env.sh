#!/usr/bin/env bash
set -euo pipefail

ORG="cursorvers"
REPO="cursorvers/fugue-orchestrator"
ENV_FILE=".env"
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
  --env-file <path>   Load env vars from file (default: .env)
  --org <name>        GitHub organization (default: cursorvers)
  --repo <owner/repo> Target repository (default: cursorvers/fugue-orchestrator)
  --apply             Apply changes (default: dry-run)
  --dry-run           Print planned updates only
  -h, --help          Show help

Notes:
  - Default mode is dry-run.
  - In apply mode, org secrets are set with visibility=selected and scoped to --repo.
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

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "${ENV_FILE}"
  set +a
elif [[ "${ENV_FILE_EXPLICIT}" == "true" ]]; then
  echo "Error: env file not found: ${ENV_FILE}" >&2
  exit 1
else
  echo "Info: ${ENV_FILE} not found; using current process environment only."
fi

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
    if printf '%s' "${RESOLVED_VALUE}" | gh secret set "${secret_name}" --org "${ORG}" --visibility selected --repos "${REPO}" >/dev/null; then
      echo "OK: set org secret ${secret_name} from ${RESOLVED_SOURCE}"
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

echo "mode=$([[ "${APPLY}" == "true" ]] && echo apply || echo dry-run) org=${ORG} repo=${REPO} env=${ENV_FILE}"

# Required
apply_secret org OPENAI_API_KEY required OPENAI_API_KEY
apply_secret org ZAI_API_KEY required ZAI_API_KEY
apply_secret repo TARGET_REPO_PAT required TARGET_REPO_PAT

# Optional providers
apply_secret org ANTHROPIC_API_KEY optional ANTHROPIC_API_KEY
apply_secret org GEMINI_API_KEY optional GEMINI_API_KEY
apply_secret org XAI_API_KEY optional XAI_API_KEY

# Ops and notification lifelines
apply_secret org FUGUE_OPS_PAT optional FUGUE_OPS_PAT
apply_secret org DISCORD_WEBHOOK_URL optional DISCORD_WEBHOOK_URL
apply_secret org DISCORD_SYSTEM_WEBHOOK optional DISCORD_SYSTEM_WEBHOOK

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
