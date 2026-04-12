#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${KERNEL_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
HEALTH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
RECOVERY_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-run-recovery.sh"
PHASE_GATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-phase-gate.sh"
RUN_COMPLETE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-run-complete.sh"
BUDGET_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
ADOPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-adopt.sh"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
SHARED_SECRETS_SCRIPT="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"
THREAD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh"
STATIC_CHECK_SCRIPT="${ROOT_DIR}/tests/test-codex-kernel-prompt.sh"

DEFAULT_LANE_COUNT="${KERNEL_BOOTSTRAP_LANE_COUNT:-6}"
DEFAULT_STALE_HOURS="${KERNEL_STALE_HOURS:-24}"
STATIC_CHECK_TIMEOUT_SEC="${DOCTOR_STATIC_CHECK_TIMEOUT_SEC:-15}"
SUMMARY_TIMEOUT_SEC="${KERNEL_DOCTOR_SUMMARY_TIMEOUT_SEC:-15}"

usage() {
  cat <<'EOF'
Usage:
  codex-kernel-guard.sh launch [purpose] [focus...]
  codex-kernel-guard.sh doctor [--all-runs]
  codex-kernel-guard.sh doctor --run <run_id>
  codex-kernel-guard.sh recover-run <run_id>
  codex-kernel-guard.sh phase-check <phase> [--uiux]
  codex-kernel-guard.sh phase-complete <phase> [--uiux]
  codex-kernel-guard.sh run-complete --summary <text> [--title <text>] [--uiux] [--no-gha] [--dry-run]
  codex-kernel-guard.sh glm-fail <note>
  codex-kernel-guard.sh budget-consume <provider> <count> <note>
  codex-kernel-guard.sh adopt-run <session:window> [purpose]

Compatibility:
  codex-kernel-guard.sh glm-reset [note]
EOF
}

die() {
  printf '%s\n' "${1:-error}" >&2
  exit "${2:-1}"
}

trim() {
  printf '%s' "${1:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

canonical_provider() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    codex) printf 'codex\n' ;;
    glm) printf 'glm\n' ;;
    gemini|gemini-cli) printf 'gemini-cli\n' ;;
    cursor|cursor-cli) printf 'cursor-cli\n' ;;
    copilot|copilot-cli) printf 'copilot-cli\n' ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

default_run_id() {
  local project purpose host ts
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  project="$(basename "${ROOT_DIR}")"
  purpose="$(trim "${1:-launch}")"
  purpose="$(printf '%s' "${purpose}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  ts="$(date '+%Y%m%dT%H%M%S')"
  printf 'launch:%s:%s:%s:%s:%s\n' "${host}" "${project}" "${purpose:-launch}" "${ts}" "$$"
}

bool_env() {
  [[ "${1:-false}" == "true" ]]
}

run_with_timeout() {
  local timeout_sec="${1:?timeout is required}"
  shift
  python3 - "${timeout_sec}" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
cmd = sys.argv[2:]

try:
    completed = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        check=False,
    )
    sys.stdout.write(completed.stdout)
    raise SystemExit(completed.returncode)
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        sys.stdout.write(exc.stdout)
    raise SystemExit(124)
PY
}

ensure_default_env() {
  export KERNEL_ROOT="${ROOT_DIR}"
}

compact_dir() {
  printf '%s\n' "${KERNEL_COMPACT_DIR:-$(bash "${STATE_PATH_SCRIPT}" compact-dir)}"
}

ledger_file() {
  printf '%s\n' "${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
}

receipt_path_for() {
  KERNEL_RUN_ID="${1:-${KERNEL_RUN_ID:-unknown-run}}" bash "${RECEIPT_SCRIPT}" path
}

compact_path_for() {
  KERNEL_RUN_ID="${1:-${KERNEL_RUN_ID:-unknown-run}}" bash "${COMPACT_SCRIPT}" path
}

jq_safe_string() {
  local expr="${1:?expr required}"
  local file="${2:?file required}"
  jq -r "${expr} // \"\"" "${file}"
}

json_compact_files() {
  local dir
  dir="$(compact_dir)"
  mkdir -p "${dir}"
  find "${dir}" -maxdepth 1 -type f -name '*.json' | sort
}

tmux_session_exists() {
  local session_name="${1:-}"
  [[ -n "${session_name}" ]] || return 1
  bool_env "${KERNEL_DOCTOR_SKIP_TMUX_CHECK:-false}" && return 0
  command -v tmux >/dev/null 2>&1 || return 1
  tmux has-session -t "=${session_name}" 2>/dev/null
}

is_stale_compact() {
  local file="${1:?file required}"
  local updated_at tmux_session now_epoch updated_epoch age_sec stale_cutoff
  tmux_session="$(jq -r '.tmux_session // ""' "${file}")"
  updated_at="$(jq -r '.updated_at // ""' "${file}")"
  stale_cutoff="$(( DEFAULT_STALE_HOURS * 3600 ))"

  if [[ -n "${tmux_session}" ]] && ! tmux_session_exists "${tmux_session}"; then
    return 0
  fi

  [[ -n "${updated_at}" ]] || return 1
  updated_epoch="$(python3 - "${updated_at}" <<'PY'
import datetime, sys
try:
    dt = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
except ValueError:
    print(-1)
    raise SystemExit(0)
print(int(dt.replace(tzinfo=datetime.timezone.utc).timestamp()))
PY
)"
  [[ "${updated_epoch}" =~ ^-?[0-9]+$ ]] || return 1
  (( updated_epoch >= 0 )) || return 1
  now_epoch="$(date -u '+%s')"
  age_sec="$(( now_epoch - updated_epoch ))"
  (( age_sec >= stale_cutoff ))
}

workspace_receipt_exists() {
  local path="${1:-}"
  [[ -n "${path}" && -f "${path}" ]]
}

ledger_json_for_run() {
  local run_id="${1:?run_id required}"
  local file
  file="$(ledger_file)"
  [[ -f "${file}" ]] || return 1
  jq -c --arg run_id "${run_id}" '.runs[$run_id] // {}' "${file}"
}

compact_json_for_run() {
  local run_id="${1:?run_id required}"
  local path
  path="$(compact_path_for "${run_id}")"
  [[ -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

print_shared_secrets_status() {
  local out
  printf 'shared secrets status:\n'
  if out="$(bash "${SHARED_SECRETS_SCRIPT}" doctor 2>/dev/null)"; then
    printf '%s\n' "${out}" | sed '1d'
  else
    printf '  - unavailable\n'
  fi
}

print_bootstrap_receipt_status() {
  local run_id="${1:?run_id required}"
  local out
  printf 'bootstrap receipt status:\n'
  if out="$(KERNEL_RUN_ID="${run_id}" bash "${RECEIPT_SCRIPT}" status 2>&1)"; then
    printf '%s\n' "${out}"
  else
    printf '%s\n' "${out}"
  fi
}

print_compact_status() {
  local run_id="${1:?run_id required}"
  local path present
  path="$(compact_path_for "${run_id}")"
  present=false
  [[ -f "${path}" ]] && present=true
  printf 'compact artifact status:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - present: %s\n' "${present}"
  printf '  - path: %s\n' "${path}"
}

print_runtime_health_status() {
  local run_id="${1:?run_id required}"
  local out rc
  printf 'runtime health status:\n'
  set +e
  out="$(run_with_timeout "${SUMMARY_TIMEOUT_SEC}" env KERNEL_RUN_ID="${run_id}" KERNEL_RUNTIME_HEALTH_MUTATE=false bash "${HEALTH_SCRIPT}" status)"
  rc=$?
  set -e
  if [[ "${rc}" -eq 124 ]]; then
    printf '  - timeout after %ss\n' "${SUMMARY_TIMEOUT_SEC}"
    return 0
  fi
  printf '%s\n' "${out}"
}

print_static_contract_status() {
  local out rc
  printf 'static contract status:\n'
  set +e
  out="$(run_with_timeout "${STATIC_CHECK_TIMEOUT_SEC}" bash "${STATIC_CHECK_SCRIPT}")"
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    printf '  - static contract: pass\n'
  else
    printf '  - static contract: fail\n'
  fi
}

print_recent_events() {
  local run_id="${1:?run_id required}"
  local file count
  file="$(ledger_file)"
  [[ -f "${file}" ]] || return 0
  count="$(jq -r --arg run_id "${run_id}" '(.runs[$run_id].events // []) | length' "${file}")"
  (( count > 0 )) || return 0
  printf 'recent events:\n'
  jq -r --arg run_id "${run_id}" '
    (.runs[$run_id].events // [])[-5:]
    | .[]
    | "  - at=\(.at // "") | actor=\(.actor // "") | command=\(.command // "") | summary=\(.summary // "")"
  ' "${file}"
}

specialist_available() {
  local provider
  provider="$(canonical_provider "${1:-}")"
  case "${provider}" in
    gemini-cli)
      [[ -n "${GEMINI_BIN:-}" && "${GEMINI_BIN}" == "false" ]] && return 1
      command -v "${GEMINI_BIN:-gemini}" >/dev/null 2>&1
      ;;
    cursor-cli)
      [[ -n "${CURSOR_BIN:-}" && "${CURSOR_BIN}" == "false" ]] && return 1
      command -v "${CURSOR_BIN:-cursor}" >/dev/null 2>&1
      ;;
    copilot-cli)
      if [[ -n "${COPILOT_BIN:-}" && "${COPILOT_BIN}" == "false" ]]; then
        return 1
      fi
      command -v "${COPILOT_BIN:-copilot}" >/dev/null 2>&1 || command -v gh >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

glm_credentials_present() {
  [[ -n "${ZAI_API_KEY:-${GLM_API_KEY:-}}" ]]
}

launch_mode() {
  env KERNEL_RUN_ID="${KERNEL_RUN_ID}" bash "${GLM_STATE_SCRIPT}" status | sed -n 's/  - mode: //p' | head -n 1
}

launch_providers_and_models() {
  local mode="${1:?mode required}"
  local providers_csv active_models_csv providers=() specialists=() candidate

  providers_csv="$(trim "${KERNEL_BOOTSTRAP_PROVIDERS_CSV:-}")"
  active_models_csv="$(trim "${KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV:-}")"

  if [[ -z "${providers_csv}" ]]; then
    if [[ "${mode}" == "degraded-allowed" ]]; then
      providers=(codex)
      for candidate in gemini-cli cursor-cli copilot-cli; do
        if specialist_available "${candidate}"; then
          providers+=("${candidate}")
        fi
        ((${#providers[@]} >= 3)) && break
      done
    else
      providers=(codex glm)
      for candidate in gemini-cli cursor-cli copilot-cli; do
        if specialist_available "${candidate}"; then
          providers+=("${candidate}")
          break
        fi
      done
    fi
    providers_csv="$(IFS=,; printf '%s' "${providers[*]}")"
  fi

  if [[ -z "${active_models_csv}" ]]; then
    if [[ "${mode}" == "degraded-allowed" ]]; then
      active_models_csv="gpt-5.3-codex"
      while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        [[ "${candidate}" == "codex" ]] && continue
        if [[ -n "${active_models_csv}" ]]; then
          active_models_csv+=",${candidate}"
        else
          active_models_csv="${candidate}"
        fi
      done < <(printf '%s\n' "${providers_csv}" | tr ',' '\n')
    else
      active_models_csv="gpt-5.3-codex,glm"
      while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        [[ "${candidate}" == "codex" || "${candidate}" == "glm" ]] && continue
        active_models_csv+=",${candidate}"
      done < <(printf '%s\n' "${providers_csv}" | tr ',' '\n')
    fi
  fi

  printf '%s\n%s\n' "${providers_csv}" "${active_models_csv}"
}

launch_validate_shape() {
  local mode="${1:?mode required}"
  local providers_csv="${2:?providers required}"
  local specialist_count=0 provider

  while IFS= read -r provider; do
    provider="$(trim "${provider}")"
    [[ -n "${provider}" ]] || continue
    case "${provider}" in
      codex|glm) ;;
      *)
        if specialist_available "${provider}"; then
          specialist_count=$((specialist_count + 1))
        fi
        ;;
    esac
  done < <(printf '%s\n' "${providers_csv}" | tr ',' '\n')

  if (( DEFAULT_LANE_COUNT < 6 )); then
    die "lane-count-below-minimum:${DEFAULT_LANE_COUNT}<6" 1
  fi

  if [[ "${mode}" == "degraded-allowed" ]]; then
    (( specialist_count >= 2 )) || die "specialists-insufficient-for-degraded:${specialist_count}<2" 1
  else
    [[ "${providers_csv}" == *"glm"* ]] || die "glm-missing-from-normal-receipt" 1
    (( specialist_count >= 1 )) || die "specialists-insufficient-for-normal:${specialist_count}<1" 1
    glm_credentials_present || die "glm-credentials-missing" 1
  fi
}

cmd_launch() {
  local purpose="${1:-launch}"
  shift || true
  local focus=("$@")
  local mode providers_csv active_models_csv prompt run_id manifest_lane_count

  ensure_default_env

  if [[ ! -f "${STATIC_CHECK_SCRIPT}" ]]; then
    die "static check missing: ${STATIC_CHECK_SCRIPT}"
  fi
  bash "${STATIC_CHECK_SCRIPT}" >/dev/null

  run_id="$(default_run_id "${purpose}")"
  export KERNEL_RUN_ID="${run_id}"
  export KERNEL_PROJECT="${KERNEL_PROJECT:-$(basename "${ROOT_DIR}")}"
  export KERNEL_PURPOSE="${KERNEL_PURPOSE:-${purpose}}"
  export KERNEL_PHASE="${KERNEL_PHASE:-requirements}"
  export KERNEL_RUNTIME="${KERNEL_RUNTIME:-kernel}"
  export KERNEL_MODE="${KERNEL_MODE:-healthy}"
  export KERNEL_OWNER="${KERNEL_OWNER:-codex}"
  export KERNEL_NEXT_ACTIONS="${KERNEL_NEXT_ACTIONS:-continue kernel run}"

  mode="$(launch_mode)"
  [[ -n "${mode}" ]] || mode="healthy"
  if [[ "${mode}" != "degraded-allowed" ]]; then
    mode="normal"
  fi

  {
    IFS= read -r providers_csv
    IFS= read -r active_models_csv
  } < <(launch_providers_and_models "${mode}")

  launch_validate_shape "${mode}" "${providers_csv}"

  manifest_lane_count="${KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT:-${DEFAULT_LANE_COUNT}}"
  export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="${active_models_csv}"
  export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="${manifest_lane_count}"
  export KERNEL_BOOTSTRAP_AGENT_LABELS="${KERNEL_BOOTSTRAP_AGENT_LABELS:-true}"
  export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="${KERNEL_BOOTSTRAP_SUBAGENT_LABELS:-true}"

  KERNEL_RUN_ID="${run_id}" bash "${RECEIPT_SCRIPT}" write "${DEFAULT_LANE_COUNT}" "${providers_csv}" "${mode}" "codex-kernel-guard launch" >/dev/null
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" scheduler-state claimed "codex-kernel-guard launch" >/dev/null
  KERNEL_RUN_ID="${run_id}" bash "${COMPACT_SCRIPT}" update status_changed "Kernel launch prepared" >/dev/null

  if [[ "${ORCH_DRY_RUN:-0}" == "1" ]]; then
    prompt="$(env KERNEL_RUN_ID="${run_id}" bash "${THREAD_SCRIPT}" prompt "${run_id}")"
    printf '%s -C %q %q\n' "${CODEX_BIN:-/opt/homebrew/bin/codex}" "${ROOT_DIR}" "${prompt}"
    return 0
  fi

  exec env KERNEL_RUN_ID="${run_id}" bash "${THREAD_SCRIPT}" launch "${run_id}"
}

cmd_doctor() {
  local scope="active"
  local run_id=""
  local file json line_count
  ensure_default_env

  while (($#)); do
    case "$1" in
      --all-runs)
        scope="all"
        shift
        ;;
      --run)
        run_id="${2:-}"
        [[ -n "${run_id}" ]] || die "--run requires a run_id" 2
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        die "Unknown option for doctor: $1" 2
        ;;
    esac
  done

  if [[ -n "${run_id}" ]]; then
    cmd_doctor_run "${run_id}"
    return 0
  fi

  printf '%s runs:\n' "${scope}"
  line_count=0
  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    if [[ "${scope}" == "active" ]] && is_stale_compact "${file}"; then
      continue
    fi
    json="$(jq -c '.' "${file}")"
    printf '  - run_id=%s | project=%s | purpose=%s | tmux_session=%s | phase=%s | mode=%s | runtime=%s | next_action=%s | updated_at=%s | stale=%s | scheduler_state=%s | workspace_receipt=%s\n' \
      "$(jq -r '.run_id // ""' <<<"${json}")" \
      "$(jq -r '.project // ""' <<<"${json}")" \
      "$(jq -r '.purpose // ""' <<<"${json}")" \
      "$(jq -r '.tmux_session // ""' <<<"${json}")" \
      "$(jq -r '.current_phase // ""' <<<"${json}")" \
      "$(jq -r '.mode // ""' <<<"${json}")" \
      "$(jq -r '.runtime // "kernel"' <<<"${json}")" \
      "$(jq -r '(.next_action // [])[0] // ""' <<<"${json}")" \
      "$(jq -r '.updated_at // ""' <<<"${json}")" \
      "$(if is_stale_compact "${file}"; then printf 'true'; else printf 'false'; fi)" \
      "$(jq -r '.scheduler_state // "unknown"' <<<"${json}")" \
      "$(if workspace_receipt_exists "$(jq -r '.workspace_receipt_path // ""' <<<"${json}")"; then printf 'true'; else printf 'false'; fi)"
    line_count=$((line_count + 1))
  done < <(json_compact_files | while IFS= read -r candidate; do
    updated_at="$(jq -r '.updated_at // ""' "${candidate}")"
    printf '%s\t%s\n' "${updated_at}" "${candidate}"
  done | sort -r | cut -f2-)

  if (( line_count == 0 )); then
    printf '  - none\n'
  fi

  print_shared_secrets_status
  print_bootstrap_receipt_status "${KERNEL_RUN_ID:-unknown-run}"
  print_runtime_health_status "${KERNEL_RUN_ID:-unknown-run}"
  print_compact_status "${KERNEL_RUN_ID:-unknown-run}"
}

cmd_doctor_run() {
  local run_id="${1:?run_id required}"
  local compact_path json phase_artifacts scheduler_state_compact workspace_receipt_path_compact
  local scheduler_state scheduler_reason workspace_receipt_path

  ensure_default_env
  compact_path="$(compact_path_for "${run_id}")"
  [[ -f "${compact_path}" ]] || die "compact artifact missing for run: ${run_id}" 1
  json="$(jq -c '.' "${compact_path}")"
  phase_artifacts="$(jq -r '
    if ((.phase_artifacts // {}) | length) == 0 then "none"
    else ((.phase_artifacts // {}) | to_entries | map("\(.key)=\(.value)") | join(" | "))
    end
  ' <<<"${json}")"
  scheduler_state_compact="$(jq -r '.scheduler_state // "unknown"' <<<"${json}")"
  workspace_receipt_path_compact="$(jq -r '.workspace_receipt_path // ""' <<<"${json}")"
  scheduler_state="$(ledger_json_for_run "${run_id}" 2>/dev/null | jq -r '.scheduler_state // "unknown"' 2>/dev/null || printf 'unknown')"
  scheduler_reason="$(ledger_json_for_run "${run_id}" 2>/dev/null | jq -r '.scheduler_reason // ""' 2>/dev/null || printf '')"
  workspace_receipt_path="$(ledger_json_for_run "${run_id}" 2>/dev/null | jq -r '.workspace_receipt_path // ""' 2>/dev/null || printf '')"

  printf 'doctor scope run id: %s\n' "${run_id}"
  print_static_contract_status
  print_shared_secrets_status
  print_runtime_health_status "${run_id}"

  printf 'run detail:\n'
  printf '  - run_id: %s\n' "${run_id}"
  printf '  - project: %s\n' "$(jq -r '.project // ""' <<<"${json}")"
  printf '  - purpose: %s\n' "$(jq -r '.purpose // ""' <<<"${json}")"
  printf '  - runtime: %s\n' "$(jq -r '.runtime // "kernel"' <<<"${json}")"
  printf '  - phase: %s\n' "$(jq -r '.current_phase // ""' <<<"${json}")"
  printf '  - mode: %s\n' "$(jq -r '.mode // ""' <<<"${json}")"
  printf '  - tmux_session: %s\n' "$(jq -r '.tmux_session // ""' <<<"${json}")"
  printf '  - codex_thread_title: %s\n' "$(jq -r '.codex_thread_title // ((.project // "") + ":" + (.purpose // ""))' <<<"${json}")"
  printf '  - active_models: %s\n' "$(jq -r '(.active_models // []) | join(",")' <<<"${json}")"
  printf '  - blocking_reason: %s\n' "$(jq -r '.blocking_reason // ""' <<<"${json}")"
  printf '  - next_action: %s\n' "$(jq -r '(.next_action // [])[0] // ""' <<<"${json}")"
  printf '  - summary: %s\n' "$(jq -r '(.summary // []) | join(" || ")' <<<"${json}")"
  printf '  - updated_at: %s\n' "$(jq -r '.updated_at // ""' <<<"${json}")"
  printf '  - scheduler_state_compact: %s\n' "${scheduler_state_compact}"
  printf '  - workspace_receipt_path_compact: %s\n' "${workspace_receipt_path_compact}"
  printf '  - phase_artifacts: %s\n' "${phase_artifacts}"

  KERNEL_RUN_ID="${run_id}" bash "${RECEIPT_SCRIPT}" status
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" status || true
  printf '  - scheduler state: %s\n' "${scheduler_state}"
  printf '  - scheduler reason: %s\n' "${scheduler_reason}"
  printf '  - workspace receipt path: %s\n' "${workspace_receipt_path}"

  printf 'compact artifact:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - path: %s\n' "${compact_path}"
  printf '  - project: %s\n' "$(jq -r '.project // ""' <<<"${json}")"
  printf '  - purpose: %s\n' "$(jq -r '.purpose // ""' <<<"${json}")"
  print_recent_events "${run_id}"
}

cmd_recover_run() {
  local run_id="${1:-}"
  [[ -n "${run_id}" ]] || die "recover-run requires a run_id" 2
  ensure_default_env
  exec env KERNEL_RUN_ID="${run_id}" bash "${RECOVERY_SCRIPT}" recover "${run_id}"
}

cmd_phase_check() {
  [[ $# -ge 1 ]] || die "phase-check requires a phase" 2
  ensure_default_env
  exec bash "${PHASE_GATE_SCRIPT}" check "$@"
}

cmd_phase_complete() {
  [[ $# -ge 1 ]] || die "phase-complete requires a phase" 2
  ensure_default_env
  exec bash "${PHASE_GATE_SCRIPT}" complete "$@"
}

cmd_run_complete() {
  ensure_default_env
  exec bash "${RUN_COMPLETE_SCRIPT}" "$@"
}

cmd_glm_fail() {
  local note="${1:-glm-failure}"
  local mode
  ensure_default_env
  bash "${GLM_STATE_SCRIPT}" fail "${note}" >/dev/null
  mode="$(env KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${GLM_STATE_SCRIPT}" status | sed -n 's/  - mode: //p' | head -n 1)"
  if [[ "${mode}" == "degraded-allowed" ]]; then
    KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${LEDGER_SCRIPT}" transition degraded-allowed "${note}" >/dev/null
  else
    KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${LEDGER_SCRIPT}" transition healthy "${note}" >/dev/null
  fi
  env KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${GLM_STATE_SCRIPT}" status
}

cmd_glm_reset() {
  local note="${1:-glm-reset}"
  ensure_default_env
  bash "${GLM_STATE_SCRIPT}" reset "${note}" >/dev/null
  KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${LEDGER_SCRIPT}" transition healthy "${note}" >/dev/null
  env KERNEL_RUN_ID="${KERNEL_RUN_ID:-unknown-run}" bash "${GLM_STATE_SCRIPT}" status
}

cmd_budget_consume() {
  local provider="${1:-}"
  local count="${2:-}"
  shift 2 || true
  local note="${*:-manual}"
  [[ -n "${provider}" && -n "${count}" ]] || die "budget-consume requires <provider> <count> <note>" 2
  ensure_default_env
  exec bash "${BUDGET_SCRIPT}" consume "${provider}" "${count}" "${note}"
}

cmd_adopt_run() {
  local target="${1:-}"
  local purpose="${2:-}"
  [[ -n "${target}" ]] || die "adopt-run requires <session:window> [purpose]" 2
  ensure_default_env
  exec bash "${ADOPT_SCRIPT}" adopt "${target}" "${purpose}"
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "${cmd}" in
    launch)
      cmd_launch "$@"
      ;;
    doctor)
      cmd_doctor "$@"
      ;;
    recover-run)
      cmd_recover_run "$@"
      ;;
    phase-check)
      cmd_phase_check "$@"
      ;;
    phase-complete)
      cmd_phase_complete "$@"
      ;;
    run-complete)
      cmd_run_complete "$@"
      ;;
    glm-fail)
      cmd_glm_fail "$@"
      ;;
    glm-reset)
      cmd_glm_reset "$@"
      ;;
    budget-consume)
      cmd_budget_consume "$@"
      ;;
    adopt-run)
      cmd_adopt_run "$@"
      ;;
    help|-h|--help|"")
      usage
      ;;
    *)
      die "Unknown command: ${cmd}" 2
      ;;
  esac
}

main "$@"
