#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-cursorvers/fugue-orchestrator}"
STATE="${STATE:-online}"
SOURCE_NAME="${SOURCE_NAME:-local-heartbeat}"
NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || hostname || echo unknown)}"
TIMESTAMP="${TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
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
  --dry-run             Print values without writing GitHub variables
  -h, --help
EOF
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

gh variable set FUGUE_PRIMARY_HEARTBEAT_AT --repo "${REPO}" --body "${TIMESTAMP}" >/dev/null
gh variable set FUGUE_PRIMARY_HEARTBEAT_NODE --repo "${REPO}" --body "${NODE_NAME}" >/dev/null
gh variable set FUGUE_PRIMARY_HEARTBEAT_STATE --repo "${REPO}" --body "${STATE}" >/dev/null
gh variable set FUGUE_PRIMARY_HEARTBEAT_SOURCE --repo "${REPO}" --body "${SOURCE_NAME}" >/dev/null

printf 'Heartbeat updated: repo=%s at=%s node=%s state=%s source=%s\n' \
  "${REPO}" "${TIMESTAMP}" "${NODE_NAME}" "${STATE}" "${SOURCE_NAME}"
