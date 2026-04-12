#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUDGET_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
AUTH_EVIDENCE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-auth-evidence.sh"
AUTH_TTL_SEC="${KERNEL_AUTH_EVIDENCE_TTL_SEC:-0}"
READY_TIMEOUT_SEC="${KERNEL_PROVIDER_READY_TIMEOUT_SEC:-5}"

usage() {
  cat <<'EOF'
Usage:
  kernel-specialist-picker.sh pick
  kernel-specialist-picker.sh status
  kernel-specialist-picker.sh ready <provider>
EOF
}

write_auth_evidence() {
  local provider="${1:?provider is required}"
  local state="${2:?state is required}"
  local note="${3:-}"
  bash "${AUTH_EVIDENCE_SCRIPT}" record "${provider}" "${state}" "${note}" >/dev/null
}

read_auth_evidence() {
  local provider="${1:?provider is required}"
  local path state saved_at note now
  path="$(KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${AUTH_EVIDENCE_SCRIPT}" path "${provider}" 2>/dev/null || true)"
  [[ -f "${path}" ]] || return 1
  state="$(jq -r '.state // ""' "${path}")"
  saved_at="$(jq -r '.updated_at_epoch // 0' "${path}")"
  note="$(jq -r '.note // ""' "${path}")"
  [[ -n "${state}" && -n "${saved_at}" ]] || return 1
  now="$(date +%s)"
  if (( AUTH_TTL_SEC > 0 && now - saved_at > AUTH_TTL_SEC )); then
    return 1
  fi
  printf '%s\t%s\n' "${state}" "${note}"
}

bounded_capture() {
  local timeout_sec="${1:?timeout is required}"
  shift
  local tmp_dir output_file rc_file pid watcher rc
  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/output.txt"
  rc_file="${tmp_dir}/rc.txt"
  (
    "$@" >"${output_file}" 2>&1
    printf '%s\n' "$?" >"${rc_file}"
  ) &
  pid=$!
  (
    sleep "${timeout_sec}"
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill -TERM "${pid}" >/dev/null 2>&1 || true
      sleep 1
      kill -KILL "${pid}" >/dev/null 2>&1 || true
      printf '124\n' >"${rc_file}"
    fi
  ) &
  watcher=$!

  wait "${pid}" >/dev/null 2>&1 || true
  kill "${watcher}" >/dev/null 2>&1 || true
  wait "${watcher}" >/dev/null 2>&1 || true

  cat "${output_file}"
  rc="$(cat "${rc_file}" 2>/dev/null || printf '1')"
  rm -rf "${tmp_dir}"
  return "${rc}"
}

cursor_status_probe() {
  local bin="${1:?cursor bin is required}"
  local output rc
  output="$(bounded_capture "${READY_TIMEOUT_SEC}" "${bin}" agent status)"
  rc=$?
  printf '%s' "${output}"
  return "${rc}"
}

copilot_status_probe() {
  local output rc
  output="$(bounded_capture "${READY_TIMEOUT_SEC}" gh copilot -- --help)"
  rc=$?
  printf '%s' "${output}"
  return "${rc}"
}

canonical_provider() {
  case "${1:-}" in
    gemini|gemini-cli) printf 'gemini-cli\n' ;;
    cursor|cursor-cli) printf 'cursor-cli\n' ;;
    copilot|copilot-cli) printf 'copilot-cli\n' ;;
    *)
      printf 'unknown\n'
      return 1
      ;;
  esac
}

cursor_ready() {
  local cached_state cached_note output rc
  if [[ -n "${KERNEL_CURSOR_READY:-}" ]]; then
    [[ "${KERNEL_CURSOR_READY}" == "true" ]]
    return
  fi

  if [[ "${KERNEL_CURSOR_KEYCHAIN_LOCKED_OK:-false}" == "true" ]]; then
    write_auth_evidence cursor-cli ready keychain-locked-ssh-ok
    return 0
  fi

  if read -r cached_state cached_note < <(read_auth_evidence cursor-cli); then
    if [[ "${cached_state}" != "ready" ]]; then
      return 1
    fi
  fi

  local bin="${KERNEL_CURSOR_BIN:-cursor}"
  command -v "${bin}" >/dev/null 2>&1 || return 1
  set +e
  output="$(cursor_status_probe "${bin}")"
  rc=$?
  set -e
  if grep -Fq 'Logged in as' <<<"${output}"; then
    write_auth_evidence cursor-cli ready logged-in
    return 0
  fi
  if grep -Fq 'Workspace Trust Required' <<<"${output}"; then
    write_auth_evidence cursor-cli not-ready workspace-trust-required
    return 1
  fi
  if grep -Fqi 'keychain is locked' <<<"${output}"; then
    write_auth_evidence cursor-cli not-ready keychain-locked
    return 1
  fi
  if [[ "${rc}" -eq 124 ]]; then
    write_auth_evidence cursor-cli not-ready status-timeout
    return 1
  fi
  write_auth_evidence cursor-cli not-ready status-unready
  return 1
}

copilot_ready() {
  local cached_state cached_note output rc
  if [[ -n "${KERNEL_COPILOT_READY:-}" ]]; then
    [[ "${KERNEL_COPILOT_READY}" == "true" ]]
    return
  fi

  if read -r cached_state cached_note < <(read_auth_evidence copilot-cli); then
    [[ "${cached_state}" == "ready" ]]
    return
  fi

  if command -v "${KERNEL_COPILOT_BIN:-copilot}" >/dev/null 2>&1; then
    write_auth_evidence copilot-cli ready copilot-binary
    return 0
  fi

  command -v gh >/dev/null 2>&1 || {
    write_auth_evidence copilot-cli not-ready unavailable
    return 1
  }
  gh auth status >/dev/null 2>&1 || {
    write_auth_evidence copilot-cli not-ready gh-auth-missing
    return 1
  }

  set +e
  output="$(copilot_status_probe)"
  rc=$?
  set -e
  if grep -Fq 'Copilot CLI not installed' <<<"${output}"; then
    write_auth_evidence copilot-cli not-ready gh-copilot-missing
    return 1
  fi
  if [[ "${rc}" -eq 0 ]]; then
    write_auth_evidence copilot-cli ready gh-copilot
    return 0
  fi

  write_auth_evidence copilot-cli not-ready gh-copilot-unready
  return 1
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
      copilot_ready
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
  local ledger_file="${KERNEL_OPTIONAL_LANE_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" optional-lane-ledger-file)}"
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
  local provider cached
  for provider in gemini-cli cursor-cli copilot-cli; do
    if provider_ready "${provider}"; then
      printf '%s\tready\t%s\n' "${provider}" "$(provider_score "${provider}")"
    else
      if cached="$(read_auth_evidence "${provider}" 2>/dev/null)"; then
        printf '%s\tnot-ready\t%s\n' "${provider}" "${cached#*$'\t'}"
      else
        printf '%s\tnot-ready\n' "${provider}"
      fi
    fi
  done
}

cmd_ready() {
  local provider
  provider="$(canonical_provider "${1:-}")" || {
    usage >&2
    exit 2
  }
  [[ "${provider}" != "auto" ]] || {
    echo "ready requires a concrete provider" >&2
    exit 2
  }
  if provider_ready "${provider}"; then
    printf 'ready\n'
  else
    printf 'not-ready\n'
    exit 1
  fi
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
  ready)
    shift || true
    cmd_ready "$@"
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
