#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUDGET_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"

usage() {
  cat <<'EOF'
Usage:
  kernel-specialist-picker.sh pick
  kernel-specialist-picker.sh status
EOF
}

cursor_ready() {
  if [[ -n "${KERNEL_CURSOR_READY:-}" ]]; then
    [[ "${KERNEL_CURSOR_READY}" == "true" ]]
    return
  fi
  local bin="${KERNEL_CURSOR_BIN:-cursor}"
  command -v "${bin}" >/dev/null 2>&1 || return 1
  local output=""
  output="$("${bin}" agent status 2>/dev/null || true)"
  grep -Fq 'Logged in as' <<<"${output}"
}

provider_ready() {
  case "${1:-}" in
    gemini-cli)
      command -v "${KERNEL_GEMINI_BIN:-gemini}" >/dev/null 2>&1
      ;;
    cursor-cli)
      cursor_ready
      ;;
    copilot-cli)
      command -v "${KERNEL_COPILOT_BIN:-copilot}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

provider_caps() {
  case "${1:-}" in
    gemini-cli)
      printf '%s %s day\n' "${KERNEL_GEMINI_DAILY_SOFT_CAP:-200}" "${KERNEL_GEMINI_PER_RUN_SOFT_CAP:-20}"
      ;;
    cursor-cli)
      printf '%s %s month\n' "${KERNEL_CURSOR_MONTHLY_SOFT_CAP:-20}" "${KERNEL_CURSOR_PER_RUN_SOFT_CAP:-1}"
      ;;
    copilot-cli)
      printf '%s %s month\n' "${KERNEL_COPILOT_MONTHLY_SOFT_CAP:-12}" "${KERNEL_COPILOT_PER_RUN_SOFT_CAP:-1}"
      ;;
    *)
      return 1
      ;;
  esac
}

provider_usage() {
  local provider="${1:-}"
  local ledger_file="${KERNEL_OPTIONAL_LANE_LEDGER_FILE:-$HOME/.config/kernel/optional-lane-usage.json}"
  local run_id="${KERNEL_RUN_ID:-unknown-run}"
  [[ -f "${ledger_file}" ]] || {
    printf '0 0\n'
    return 0
  }
  local period_key period_kind
  read -r _ _ period_kind < <(provider_caps "${provider}")
  if [[ "${period_kind}" == "day" ]]; then
    period_key="$(date '+%Y-%m-%d')"
    jq -r --arg provider "${provider}" --arg day "${period_key}" --arg run_id "${run_id}" '
      [
        ([.events[] | select(.provider == $provider and (.day // "") == $day) | (.units // 0)] | add // 0),
        ([.events[] | select(.provider == $provider and (.run_id // "") == $run_id) | (.units // 0)] | add // 0)
      ] | @tsv
    ' "${ledger_file}"
  else
    period_key="$(date '+%Y-%m')"
    jq -r --arg provider "${provider}" --arg month "${period_key}" --arg run_id "${run_id}" '
      [
        ([.events[] | select(.provider == $provider and (.month // "") == $month) | (.units // 0)] | add // 0),
        ([.events[] | select(.provider == $provider and (.run_id // "") == $run_id) | (.units // 0)] | add // 0)
      ] | @tsv
    ' "${ledger_file}"
  fi
}

provider_score() {
  local provider="${1:-}"
  local period_cap run_cap used run_used remaining_period remaining_run
  read -r period_cap run_cap _ < <(provider_caps "${provider}")
  read -r used run_used < <(provider_usage "${provider}")
  remaining_period=$((period_cap - used))
  remaining_run=$((run_cap - run_used))
  if (( remaining_period <= 0 || remaining_run <= 0 )); then
    printf -- '-1 %s %s %s\n' "${remaining_period}" "${remaining_run}" "${provider}"
    return 0
  fi
  python3 - "$period_cap" "$run_cap" "$remaining_period" "$remaining_run" "$provider" <<'PY'
import sys
period_cap, run_cap, remaining_period, remaining_run, provider = sys.argv[1:]
period_cap = int(period_cap)
run_cap = int(run_cap)
remaining_period = int(remaining_period)
remaining_run = int(remaining_run)
score = min(remaining_period / period_cap, remaining_run / run_cap)
print(f"{score:.6f} {remaining_period} {remaining_run} {provider}")
PY
}

cmd_pick() {
  local best_line="" line provider
  for provider in gemini-cli cursor-cli copilot-cli; do
    provider_ready "${provider}" || continue
    line="$(provider_score "${provider}")"
    if [[ -z "${best_line}" ]]; then
      best_line="${line}"
      continue
    fi
    if [[ "$(BEST="${best_line}" CAND="${line}" python3 - <<'PY'
import os
def parse(line):
    score, rem_period, rem_run, provider = line.split()
    return float(score), int(rem_period), int(rem_run), provider
best = parse(os.environ["BEST"])
cand = parse(os.environ["CAND"])
print("cand" if cand > best else "best")
PY
)" == "cand" ]]; then
      best_line="${line}"
    fi
  done
  [[ -n "${best_line}" ]] || {
    echo "no specialist available" >&2
    exit 1
  }
  printf '%s\n' "${best_line##* }"
}

cmd_status() {
  local provider
  for provider in gemini-cli cursor-cli copilot-cli; do
    if provider_ready "${provider}"; then
      printf '%s\tready\t%s\n' "${provider}" "$(provider_score "${provider}")"
    else
      printf '%s\tnot-ready\n' "${provider}"
    fi
  done
}

cmd="${1:-pick}"
case "${cmd}" in
  pick)
    shift || true
    cmd_pick "$@"
    ;;
  status)
    shift || true
    cmd_status "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
