#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PULSE_SCRIPT="${ROOT_DIR}/scripts/local/pulse-primary-heartbeat.sh"

REPO="${REPO:-cursorvers/fugue-orchestrator}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
PULSE_TIMEOUT_SECONDS="${PULSE_TIMEOUT_SECONDS:-45}"
STATE="${STATE:-online}"
SOURCE_NAME="${SOURCE_NAME:-launchd-loop}"
NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || hostname || echo unknown)}"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/run-primary-heartbeat-loop.sh [options]

Options:
  --repo <owner/repo>      Target repository (default: cursorvers/fugue-orchestrator)
  --interval <seconds>     Pulse interval in seconds (default: 60)
  --timeout <seconds>      Per-pulse timeout before the loop kills a stuck heartbeat (default: 45)
  --state <state>          Steady-state label (default: online)
  --source <name>          Heartbeat source label (default: launchd-loop)
  --node <name>            Node name/host label
  --once                   Send one heartbeat and exit
  -h, --help
EOF
}

once="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --timeout)
      PULSE_TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --state)
      STATE="${2:-}"
      shift 2
      ;;
    --source)
      SOURCE_NAME="${2:-}"
      shift 2
      ;;
    --node)
      NODE_NAME="${2:-}"
      shift 2
      ;;
    --once)
      once="true"
      shift 1
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

if ! [[ "${INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${INTERVAL_SECONDS}" == "0" ]]; then
  echo "Error: --interval must be a positive integer." >&2
  exit 2
fi

if ! [[ "${PULSE_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${PULSE_TIMEOUT_SECONDS}" == "0" ]]; then
  echo "Error: --timeout must be a positive integer." >&2
  exit 2
fi

if [[ ! -x "${PULSE_SCRIPT}" ]]; then
  echo "Error: heartbeat pulse script is not executable: ${PULSE_SCRIPT}" >&2
  exit 2
fi

pulse() {
  "${PULSE_SCRIPT}" \
    --repo "${REPO}" \
    --state "${STATE}" \
    --source "${SOURCE_NAME}" \
    --node "${NODE_NAME}"
}

pulse_with_timeout() {
  local pulse_pid watcher_pid status

  pulse &
  pulse_pid=$!
  (
    sleep "${PULSE_TIMEOUT_SECONDS}"
    kill -TERM "${pulse_pid}" >/dev/null 2>&1 || true
    sleep 5
    kill -KILL "${pulse_pid}" >/dev/null 2>&1 || true
  ) &
  watcher_pid=$!

  if wait "${pulse_pid}"; then
    status=0
  else
    status=$?
  fi

  kill -TERM "${watcher_pid}" >/dev/null 2>&1 || true
  wait "${watcher_pid}" >/dev/null 2>&1 || true

  return "${status}"
}

shutdown_pulse() {
  "${PULSE_SCRIPT}" \
    --repo "${REPO}" \
    --state "stopping" \
    --source "${SOURCE_NAME}" \
    --node "${NODE_NAME}" >/dev/null 2>&1 || true
}

trap shutdown_pulse EXIT INT TERM

if [[ "${once}" == "true" ]]; then
  pulse
  exit 0
fi

while true; do
  if ! pulse_with_timeout; then
    printf 'Heartbeat pulse failed or timed out: repo=%s source=%s timeout=%ss\n' \
      "${REPO}" "${SOURCE_NAME}" "${PULSE_TIMEOUT_SECONDS}" >&2
  fi
  sleep "${INTERVAL_SECONDS}"
done
