#!/usr/bin/env bash
set -euo pipefail

ORG="cursorvers"
CONFIG="scripts/org-secrets-audit.json"
ENV_FILE=""
APPLY="false"

usage() {
  cat <<'EOF'
Usage: scripts/local/sync-gh-secrets-matrix.sh [options]

Options:
  --org <name>         GitHub organization (default: cursorvers)
  --config <path>      Audit/migration config (default: scripts/org-secrets-audit.json)
  --env-file <path>    Explicit external env file
  --apply              Apply changes
  --dry-run            Dry-run only (default)
  -h, --help           Show help

Behavior:
  - Reads configured repos from org-secrets-audit.json
  - Calls sync-gh-secrets-from-env.sh once per repo
  - Preserves selected-repo coverage for org secrets
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      ORG="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if [[ ! -f "${CONFIG}" ]]; then
  echo "Error: config not found: ${CONFIG}" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not found" >&2
  exit 1
fi

mode_flag="--dry-run"
if [[ "${APPLY}" == "true" ]]; then
  mode_flag="--apply"
fi

repos_raw="$(jq -r '.repos | keys[]' "${CONFIG}")"
if [[ -z "${repos_raw}" ]]; then
  echo "Error: no repos configured in ${CONFIG}" >&2
  exit 1
fi

printf '%s\n' "${repos_raw}" | while IFS= read -r repo; do
  [[ -z "${repo}" ]] && continue
  echo "=== sync ${repo} (${mode_flag}) ==="
  args=(
    --org "${ORG}"
    --repo "${repo}"
    "${mode_flag}"
  )
  if [[ -n "${ENV_FILE}" ]]; then
    args+=(--env-file "${ENV_FILE}")
  fi
  bash scripts/local/sync-gh-secrets-from-env.sh "${args[@]}"
  echo ""
done

echo "Done."
