#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-cursorvers/fugue-orchestrator}"
STATE="${STATE:-online}"
SOURCE_NAME="${SOURCE_NAME:-local-heartbeat}"
NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || hostname || echo unknown)}"
TIMESTAMP="${TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
MAX_FUTURE_SKEW_SECONDS="${MAX_FUTURE_SKEW_SECONDS:-300}"
GH_VARIABLE_SET_TIMEOUT_SECONDS="${GH_VARIABLE_SET_TIMEOUT_SECONDS:-10}"
dry_run="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/pulse-primary-heartbeat.sh [options]

Options:
  --repo <owner/repo>   Target repository (default: cursorvers/fugue-orchestrator)
  --state <state>       Heartbeat state label (default: online)
  --source <name>       Heartbeat source label (default: local-heartbeat)
  --node <name>         Node name/host label (default: hostname -s)
  --timestamp <iso8601> Override heartbeat timestamp
  Environment:
    FUGUE_HEARTBEAT_GH_TOKEN  Preferred dedicated GitHub token for heartbeat writes
  --dry-run             Print values without writing GitHub variables
  -h, --help
EOF
}

epoch_now_utc() {
  date -u +%s
}

iso_to_epoch_utc() {
  local iso="$1"
  if date -u -d "${iso}" +%s >/dev/null 2>&1; then
    date -u -d "${iso}" +%s
  elif date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${iso}" +%s >/dev/null 2>&1; then
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${iso}" +%s
  else
    return 1
  fi
}

resolve_gh_token() {
  local token="${FUGUE_HEARTBEAT_GH_TOKEN:-${GH_TOKEN:-}}"
  if [[ -z "${token}" ]]; then
    token="$(gh auth token 2>/dev/null || true)"
  fi
  if [[ -z "${token}" ]]; then
    echo "Error: no GitHub token available for heartbeat writes." >&2
    return 1
  fi
  printf '%s' "${token}"
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local cmd_pid watchdog_pid status

  "$@" &
  cmd_pid=$!
  (
    sleep "${timeout_seconds}"
    kill -TERM "${cmd_pid}" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL "${cmd_pid}" >/dev/null 2>&1 || true
  ) &
  watchdog_pid=$!

  if wait "${cmd_pid}"; then
    status=0
  else
    status=$?
  fi

  kill -TERM "${watchdog_pid}" >/dev/null 2>&1 || true
  wait "${watchdog_pid}" >/dev/null 2>&1 || true

  return "${status}"
}

set_heartbeat_variable() {
  local name="$1"
  local value="$2"
  if ! run_with_timeout "${GH_VARIABLE_SET_TIMEOUT_SECONDS}" \
    gh variable set "${name}" --repo "${REPO}" --body "${value}" >/dev/null; then
    echo "Error: failed to update ${name} within ${GH_VARIABLE_SET_TIMEOUT_SECONDS}s." >&2
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
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
    --timestamp)
      TIMESTAMP="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
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

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh command is required." >&2
  exit 2
fi

export GH_PROMPT_DISABLED="${GH_PROMPT_DISABLED:-1}"
export GH_NO_UPDATE_NOTIFIER="${GH_NO_UPDATE_NOTIFIER:-1}"

if ! [[ "${MAX_FUTURE_SKEW_SECONDS}" =~ ^[0-9]+$ ]]; then
  MAX_FUTURE_SKEW_SECONDS="300"
fi
if ! [[ "${GH_VARIABLE_SET_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${GH_VARIABLE_SET_TIMEOUT_SECONDS}" == "0" ]]; then
  GH_VARIABLE_SET_TIMEOUT_SECONDS="10"
fi

if ! timestamp_epoch="$(iso_to_epoch_utc "${TIMESTAMP}" 2>/dev/null)"; then
  echo "Error: invalid --timestamp value: ${TIMESTAMP}" >&2
  exit 2
fi

now_epoch="$(epoch_now_utc)"
if (( timestamp_epoch > now_epoch + MAX_FUTURE_SKEW_SECONDS )); then
  echo "Error: heartbeat timestamp is too far in the future: ${TIMESTAMP}" >&2
  exit 2
fi

if [[ "${dry_run}" == "true" ]]; then
  cat <<EOF
repo=${REPO}
timestamp=${TIMESTAMP}
node=${NODE_NAME}
state=${STATE}
source=${SOURCE_NAME}
EOF
  exit 0
fi

export GH_TOKEN="$(resolve_gh_token)"

set_heartbeat_variable FUGUE_PRIMARY_HEARTBEAT_NODE "${NODE_NAME}"
set_heartbeat_variable FUGUE_PRIMARY_HEARTBEAT_STATE "${STATE}"
set_heartbeat_variable FUGUE_PRIMARY_HEARTBEAT_SOURCE "${SOURCE_NAME}"
set_heartbeat_variable FUGUE_PRIMARY_HEARTBEAT_AT "${TIMESTAMP}"

printf 'Heartbeat updated: repo=%s at=%s node=%s state=%s source=%s\n' \
  "${REPO}" "${TIMESTAMP}" "${NODE_NAME}" "${STATE}" "${SOURCE_NAME}"
