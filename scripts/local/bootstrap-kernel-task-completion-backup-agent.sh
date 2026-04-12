#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNNER="${RUNNER:-${REPO_ROOT}/scripts/local/run-kernel-task-completion-backup.sh}"
PLIST_PATH="${PLIST_PATH:-${HOME}/Library/LaunchAgents/com.cursorvers.kernel-task-completion-backup.plist}"
AGENT_LABEL="${AGENT_LABEL:-com.cursorvers.kernel-task-completion-backup}"
LOG_DIR="${LOG_DIR:-${HOME}/Dev/kernel-orchestration-tools/logs}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-30}"
dry_run="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/bootstrap-kernel-task-completion-backup-agent.sh [options]

Options:
  --plist <path>       LaunchAgent plist path
  --label <label>      LaunchAgent label
  --runner <path>      Runner script path
  --log-dir <path>     launchd stdout/stderr directory
  --interval <sec>     StartInterval seconds (default: 30)
  --dry-run            Print the generated plist and launchctl commands
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plist)
      PLIST_PATH="${2:-}"
      shift 2
      ;;
    --label)
      AGENT_LABEL="${2:-}"
      shift 2
      ;;
    --runner)
      RUNNER="${2:-}"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="${2:-}"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
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

if [[ ! -x "${RUNNER}" ]]; then
  echo "Runner is not executable: ${RUNNER}" >&2
  exit 2
fi

mkdir -p "$(dirname "${PLIST_PATH}")" "${LOG_DIR}"

plist_contents="$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>${INTERVAL_SECONDS}</integer>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${RUNNER}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${REPO_ROOT}</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/kernel-task-completion-backup.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/kernel-task-completion-backup.log</string>
  </dict>
</plist>
EOF
)"

if [[ "${dry_run}" == "true" ]]; then
  printf '%s\n' "${plist_contents}"
  echo "launchctl bootout gui/$(id -u) ${PLIST_PATH}"
  echo "launchctl bootstrap gui/$(id -u) ${PLIST_PATH}"
  echo "launchctl kickstart -k gui/$(id -u)/${AGENT_LABEL}"
  exit 0
fi

printf '%s\n' "${plist_contents}" > "${PLIST_PATH}"
launchctl bootout "gui/$(id -u)" "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
launchctl kickstart -k "gui/$(id -u)/${AGENT_LABEL}"
