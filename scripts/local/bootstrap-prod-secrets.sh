#!/usr/bin/env bash
set -euo pipefail

ORG="cursorvers"
REPO="cursorvers/fugue-orchestrator"
ENV_FILE=""
APPLY="false"
SKIP_AUDIT="false"
FREEE_ENVIRONMENT="${FUGUE_FREEE_READONLY_ENV:-freee-readonly}"

usage() {
  cat <<'EOF'
Usage: scripts/local/bootstrap-prod-secrets.sh [options]

Options:
  --env-file <path>   Load secrets from an external env file
  --org <name>        GitHub organization (default: cursorvers)
  --repo <owner/repo> Target repository (default: cursorvers/fugue-orchestrator)
  --freee-env <name>  Protected environment for freee readonly secrets/vars
  --apply             Apply secret updates
  --dry-run           Dry-run only (default)
  --skip-audit        Skip org/repo coverage audit
  -h, --help          Show help

Flow:
  1) Ensure gh auth is valid
  2) Sync secrets/vars from process env or explicit env file -> GitHub (org/repo)
  3) Audit org secret coverage (unless --skip-audit)

NotebookLM production vars recognized from env:
  - FUGUE_NOTEBOOKLM_RUNTIME_ENV
  - FUGUE_NOTEBOOKLM_RUNTIME_ENABLED
  - FUGUE_NOTEBOOKLM_REQUIRE_RUNTIME_AUTH
  - FUGUE_NOTEBOOKLM_SENSITIVITY
  - FUGUE_NOTEBOOKLM_BIN
  - FUGUE_NOTEBOOKLM_AUTH_TOKEN
  - FUGUE_NOTEBOOKLM_COOKIES
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
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
    --freee-env)
      FREEE_ENVIRONMENT="${2:-}"
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
    --skip-audit)
      SKIP_AUDIT="true"
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found." >&2
  exit 1
fi

if ! gh auth status --active -h github.com >/dev/null 2>&1; then
  echo "Error: gh auth is not ready. Run: gh auth login -h github.com -s admin:org,repo,workflow" >&2
  exit 1
fi

mode_flag="--dry-run"
if [[ "${APPLY}" == "true" ]]; then
  mode_flag="--apply"
fi

echo "[1/2] Sync secrets (${mode_flag})"
sync_args=(
  --org "${ORG}"
  --repo "${REPO}"
  --freee-env "${FREEE_ENVIRONMENT}"
  "${mode_flag}"
)

if [[ -n "${ENV_FILE}" ]]; then
  sync_args+=(--env-file "${ENV_FILE}")
fi

bash scripts/local/sync-gh-secrets-from-env.sh "${sync_args[@]}"

if [[ "${SKIP_AUDIT}" == "true" ]]; then
  echo "[2/2] Audit skipped by --skip-audit"
  exit 0
fi

echo "[2/2] Audit org/repo secret coverage"
bash scripts/audit-org-secrets.sh --org "${ORG}" --repo "${REPO}"

echo "Done."
