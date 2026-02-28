#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/.fugue/local-run"
RUN_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/local/claude-handoff-summary.sh [--run-dir <path>] [--out-dir <path>]

Options:
  --run-dir <path>  Specific local orchestration run directory
  --out-dir <path>  Base local run directory (default: .fugue/local-run)
  -h, --help        Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 2
fi

if [[ -z "${RUN_DIR}" ]]; then
  RUN_DIR="$(ls -dt "${OUT_DIR}"/issue-* 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${RUN_DIR}" || ! -d "${RUN_DIR}" ]]; then
  echo "No local run directory found." >&2
  exit 1
fi

all_results="${RUN_DIR}/all-results.json"
if [[ ! -f "${all_results}" ]]; then
  echo "Missing artifact: ${all_results}" >&2
  exit 1
fi

sessions_json="$(jq -c '
  [ .[]
    | select((.provider // "" | ascii_downcase) == "claude")
    | select((.session_id // "") != "")
    | {name, model, session_id}
  ]
' "${all_results}")"

count="$(echo "${sessions_json}" | jq 'length')"
echo "Run directory: ${RUN_DIR}"
echo "Claude sessions: ${count}"
if [[ "${count}" -eq 0 ]]; then
  echo "No Claude session IDs found in this run."
  exit 0
fi

echo
echo "${sessions_json}" | jq -r '
  .[]
  | "- " + .name + " (" + .model + ")\n  session_id: " + .session_id + "\n  resume: claude --resume " + .session_id
'
