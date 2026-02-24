#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
PROJECT_DIR="${AUTO_VIDEO_PROJECT_DIR:-/Users/masayuki/Dev/telop-pack-srt-02}"
SMOKE_COMMAND="${AUTO_VIDEO_SMOKE_COMMAND:-npm run -s test:smoke}"
EXECUTE_COMMAND="${AUTO_VIDEO_EXECUTE_COMMAND:-npm run -s test:smoke}"

usage() {
  cat <<'EOF'
Usage: auto-video.sh [options]

Options:
  --mode <smoke|execute>   Run mode (default: smoke)
  --run-dir <path>         FUGUE run directory (optional)
  -h, --help               Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="${2:-}"
      shift 2
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

if [[ "${MODE}" != "smoke" && "${MODE}" != "execute" ]]; then
  echo "Error: --mode must be smoke|execute" >&2
  exit 2
fi

[[ -d "${PROJECT_DIR}" ]] || { echo "auto-video: missing project dir: ${PROJECT_DIR}" >&2; exit 1; }
[[ -f "${PROJECT_DIR}/package.json" ]] || { echo "auto-video: missing package.json" >&2; exit 1; }

if [[ "${MODE}" == "smoke" ]]; then
  cmd="${SMOKE_COMMAND}"
else
  cmd="${EXECUTE_COMMAND}"
fi

echo "auto-video: mode=${MODE} project=${PROJECT_DIR}"
(
  cd "${PROJECT_DIR}"
  bash -lc "${cmd}"
)

if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
  {
    echo "system=auto-video"
    echo "mode=${MODE}"
    echo "project_dir=${PROJECT_DIR}"
    echo "command=${cmd}"
  } > "${RUN_DIR}/auto-video.meta"
fi
