#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-cursorvers/fugue-orchestrator}"
PLIST_PATH="${PLIST_PATH:-${HOME}/Library/LaunchAgents/com.cursorvers.fugue-primary-heartbeat.plist}"
AGENT_LABEL="${AGENT_LABEL:-com.cursorvers.fugue-primary-heartbeat}"
SOURCE_NAME="${SOURCE_NAME:-bootstrap}"
STATE_NAME="${STATE_NAME:-online}"
NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || hostname || echo unknown)}"
dry_run="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/bootstrap-primary-heartbeat-agent.sh [options]

Options:
  --repo <owner/repo>   Target repository (default: cursorvers/fugue-orchestrator)
  --plist <path>        LaunchAgent plist path
  --label <label>       LaunchAgent label
  --source <name>       Heartbeat source label for the bootstrap pulse
  --state <state>       Heartbeat state label for the bootstrap pulse
  --node <name>         Node name/host label for the bootstrap pulse
  Environment:
    FUGUE_HEARTBEAT_GH_TOKEN  Preferred dedicated token for launchd heartbeat writes
  --dry-run             Print the commands without executing them
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --plist)
      PLIST_PATH="${2:-}"
      shift 2
      ;;
    --label)
      AGENT_LABEL="${2:-}"
      shift 2
      ;;
    --source)
      SOURCE_NAME="${2:-}"
      shift 2
      ;;
    --state)
      STATE_NAME="${2:-}"
      shift 2
      ;;
    --node)
      NODE_NAME="${2:-}"
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

if ! command -v launchctl >/dev/null 2>&1; then
  echo "Error: launchctl command is required." >&2
  exit 2
fi

if [[ ! -f "${PLIST_PATH}" ]]; then
  echo "Error: LaunchAgent plist not found: ${PLIST_PATH}" >&2
  exit 2
fi

user_domain="gui/$(id -u)"

if [[ "${dry_run}" == "true" ]]; then
  cat <<EOF
launchctl bootout ${user_domain} ${PLIST_PATH}
launchctl bootstrap ${user_domain} ${PLIST_PATH}
launchctl kickstart -k ${user_domain}/${AGENT_LABEL}
$(dirname "$0")/pulse-primary-heartbeat.sh --repo ${REPO} --source ${SOURCE_NAME} --state ${STATE_NAME} --node ${NODE_NAME}
EOF
  exit 0
fi

launchctl bootout "${user_domain}" "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl bootstrap "${user_domain}" "${PLIST_PATH}"
launchctl kickstart -k "${user_domain}/${AGENT_LABEL}"
"$(dirname "$0")/pulse-primary-heartbeat.sh" \
  --repo "${REPO}" \
  --source "${SOURCE_NAME}" \
  --state "${STATE_NAME}" \
  --node "${NODE_NAME}"
