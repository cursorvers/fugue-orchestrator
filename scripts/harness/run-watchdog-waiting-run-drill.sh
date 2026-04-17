#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POLICY_SCRIPT="${ROOT_DIR}/scripts/lib/watchdog-alert-policy.sh"

waiting_run_count="1"
waiting_run_age_minutes="61"
waiting_run_oldest="drill-workflow/123"
persist_state="false"
previous_state_json='{}'
format="json"

usage() {
  cat <<'EOF'
Usage:
  run-watchdog-waiting-run-drill.sh [options]

Options:
  --waiting-run-count <n>        Simulated waiting workflow count (default: 1)
  --waiting-run-age-minutes <n>  Simulated oldest waiting age (default: 61)
  --waiting-run-oldest <label>   Simulated oldest waiting run label
  --persist-state <true|false>   Whether policy should calculate persisted state
  --previous-state-json <json>   Previous watchdog alert state JSON
  --format <json|env>            Output format passed to policy

This is a deterministic local drill. It does not query or mutate GitHub.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --waiting-run-count)
      waiting_run_count="${2:-}"
      shift 2
      ;;
    --waiting-run-age-minutes)
      waiting_run_age_minutes="${2:-}"
      shift 2
      ;;
    --waiting-run-oldest)
      waiting_run_oldest="${2:-}"
      shift 2
      ;;
    --persist-state)
      persist_state="${2:-}"
      shift 2
      ;;
    --previous-state-json)
      previous_state_json="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

bash "${POLICY_SCRIPT}" \
  --event-name schedule \
  --failover-state healthy \
  --failover-reason primary-heartbeat-fresh \
  --gha-execution-mode full \
  --runner-online-count 1 \
  --heartbeat-status fresh \
  --heartbeat-age-minutes 1 \
  --router-hours 0 \
  --router-minutes 5 \
  --mainframe-hours 0 \
  --mainframe-minutes 5 \
  --pending-count 0 \
  --mainframe-pending-count 0 \
  --waiting-run-count "${waiting_run_count}" \
  --waiting-run-age-minutes "${waiting_run_age_minutes}" \
  --waiting-run-oldest "${waiting_run_oldest}" \
  --persist-state "${persist_state}" \
  --previous-state-json "${previous_state_json}" \
  --format "${format}"
