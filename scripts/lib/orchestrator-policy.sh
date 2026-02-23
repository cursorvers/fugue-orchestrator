#!/usr/bin/env bash
set -euo pipefail

# Resolve per-issue orchestrator policy with shared fallback/pressure guards.
# Modified FUGUE invariant: when main=claude, assist is finalized to codex
# in normal operation (unless explicit --force-claude=true override).
# Output format is shell env assignments by default so callers can `eval`.
#
# Example:
#   eval "$(
#     scripts/lib/orchestrator-policy.sh \
#       --main claude \
#       --assist claude \
#       --default-main codex \
#       --default-assist claude \
#       --claude-state degraded \
#       --force-claude false \
#       --assist-policy codex
#   )"

main=""
assist=""
default_main="codex"
default_assist="claude"
claude_state="ok"
force_claude="false"
assist_policy="codex"
claude_role_policy="flex"
degraded_assist_policy="claude"
format="env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main)
      main="${2:-}"
      shift 2
      ;;
    --assist)
      assist="${2:-}"
      shift 2
      ;;
    --default-main)
      default_main="${2:-}"
      shift 2
      ;;
    --default-assist)
      default_assist="${2:-}"
      shift 2
      ;;
    --claude-state)
      claude_state="${2:-}"
      shift 2
      ;;
    --force-claude)
      force_claude="${2:-false}"
      shift 2
      ;;
    --assist-policy)
      assist_policy="${2:-codex}"
      shift 2
      ;;
    --claude-role-policy)
      claude_role_policy="${2:-flex}"
      shift 2
      ;;
    --degraded-assist-policy)
      degraded_assist_policy="${2:-claude}"
      shift 2
      ;;
    --format)
      format="${2:-env}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: orchestrator-policy.sh [options]

Options:
  --main VALUE              Requested main orchestrator (codex|claude)
  --assist VALUE            Requested assist orchestrator (claude|codex|none)
  --default-main VALUE      Default main orchestrator when --main is empty
  --default-assist VALUE    Default assist orchestrator when --assist is empty
  --claude-state VALUE      Claude rate-limit state (ok|degraded|exhausted)
  --force-claude VALUE      true to bypass fallback/pressure guards
  --assist-policy VALUE     Guard policy for main=claude+assist=claude (codex|none)
  --claude-role-policy      Claude role policy (sub-only|flex). Default: flex
  --degraded-assist-policy  Fallback for assist=claude when state=degraded (none|codex|claude)
  --format VALUE            env (default) or json
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

lower_trim() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

normalize_main() {
  local v
  v="$(lower_trim "$1")"
  if [[ "$v" != "claude" && "$v" != "codex" ]]; then
    v=""
  fi
  printf '%s' "$v"
}

normalize_assist() {
  local v
  v="$(lower_trim "$1")"
  if [[ "$v" != "claude" && "$v" != "codex" && "$v" != "none" ]]; then
    v=""
  fi
  printf '%s' "$v"
}

requested_main="$(normalize_main "${main}")"
if [[ -z "${requested_main}" ]]; then
  requested_main="$(normalize_main "${default_main}")"
fi
if [[ -z "${requested_main}" ]]; then
  requested_main="codex"
fi

requested_assist="$(normalize_assist "${assist}")"
if [[ -z "${requested_assist}" ]]; then
  requested_assist="$(normalize_assist "${default_assist}")"
fi
if [[ -z "${requested_assist}" ]]; then
  requested_assist="claude"
fi

force_claude="$(lower_trim "${force_claude}")"
if [[ "${force_claude}" != "true" ]]; then
  force_claude="false"
fi

claude_state="$(lower_trim "${claude_state}")"
if [[ "${claude_state}" != "ok" && "${claude_state}" != "degraded" && "${claude_state}" != "exhausted" ]]; then
  claude_state="ok"
fi

assist_policy="$(lower_trim "${assist_policy}")"
if [[ "${assist_policy}" != "codex" && "${assist_policy}" != "none" ]]; then
  assist_policy="codex"
fi

claude_role_policy="$(lower_trim "${claude_role_policy}")"
if [[ "${claude_role_policy}" != "sub-only" && "${claude_role_policy}" != "flex" ]]; then
  claude_role_policy="flex"
fi

degraded_assist_policy="$(normalize_assist "${degraded_assist_policy}")"
if [[ "${degraded_assist_policy}" != "codex" && "${degraded_assist_policy}" != "none" && "${degraded_assist_policy}" != "claude" ]]; then
  degraded_assist_policy="claude"
fi

resolved_main="${requested_main}"
resolved_assist="${requested_assist}"

main_fallback_applied="false"
main_fallback_reason=""
if [[ "${resolved_main}" == "claude" && "${claude_role_policy}" == "sub-only" && "${force_claude}" != "true" ]]; then
  resolved_main="codex"
  main_fallback_applied="true"
  main_fallback_reason="claude-main-sub-only"
fi
if [[ "${resolved_main}" == "claude" && "${claude_state}" != "ok" && "${force_claude}" != "true" ]]; then
  resolved_main="codex"
  main_fallback_applied="true"
  main_fallback_reason="claude-rate-limit-${claude_state}"
fi

assist_fallback_applied="false"
assist_fallback_reason=""
if [[ "${resolved_assist}" == "claude" && "${claude_state}" == "degraded" && "${force_claude}" != "true" ]]; then
  resolved_assist="${degraded_assist_policy}"
  assist_fallback_applied="true"
  assist_fallback_reason="claude-rate-limit-degraded->${resolved_assist}"
fi
if [[ "${resolved_assist}" == "claude" && "${claude_state}" == "exhausted" && "${force_claude}" != "true" ]]; then
  resolved_assist="none"
  assist_fallback_applied="true"
  assist_fallback_reason="claude-rate-limit-${claude_state}"
fi

pressure_guard_applied="false"
pressure_guard_reason=""
if [[ "${resolved_main}" == "claude" && "${resolved_assist}" == "claude" && "${force_claude}" != "true" ]]; then
  resolved_assist="${assist_policy}"
  pressure_guard_applied="true"
  pressure_guard_reason="main-claude-assist-claude->${resolved_assist}"
fi

# Architectural invariant:
# when Claude owns the main lane, Codex must be the sub/co-orchestrator lane.
if [[ "${resolved_main}" == "claude" && "${resolved_assist}" != "codex" && "${force_claude}" != "true" ]]; then
  resolved_assist="codex"
  if [[ "${pressure_guard_applied}" != "true" ]]; then
    pressure_guard_applied="true"
    pressure_guard_reason="main-claude-requires-assist-codex"
  fi
fi

compat_label="codex-implement"
if [[ "${resolved_main}" == "claude" ]]; then
  compat_label="claude-implement"
fi

orchestrator_label="orchestrator:${resolved_main}"
assist_orchestrator_label="orchestrator-assist:${resolved_assist}"

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg requested_main "${requested_main}" \
    --arg requested_assist "${requested_assist}" \
    --arg resolved_main "${resolved_main}" \
    --arg resolved_assist "${resolved_assist}" \
    --arg main_fallback_applied "${main_fallback_applied}" \
    --arg main_fallback_reason "${main_fallback_reason}" \
    --arg assist_fallback_applied "${assist_fallback_applied}" \
    --arg assist_fallback_reason "${assist_fallback_reason}" \
    --arg pressure_guard_applied "${pressure_guard_applied}" \
    --arg pressure_guard_reason "${pressure_guard_reason}" \
    --arg claude_role_policy "${claude_role_policy}" \
    --arg degraded_assist_policy "${degraded_assist_policy}" \
    --arg compat_label "${compat_label}" \
    --arg orchestrator_label "${orchestrator_label}" \
    --arg assist_orchestrator_label "${assist_orchestrator_label}" \
    '{
      requested_main:$requested_main,
      requested_assist:$requested_assist,
      resolved_main:$resolved_main,
      resolved_assist:$resolved_assist,
      main_fallback_applied:($main_fallback_applied == "true"),
      main_fallback_reason:$main_fallback_reason,
      assist_fallback_applied:($assist_fallback_applied == "true"),
      assist_fallback_reason:$assist_fallback_reason,
      pressure_guard_applied:($pressure_guard_applied == "true"),
      pressure_guard_reason:$pressure_guard_reason,
      claude_role_policy:$claude_role_policy,
      degraded_assist_policy:$degraded_assist_policy,
      compat_label:$compat_label,
      orchestrator_label:$orchestrator_label,
      assist_orchestrator_label:$assist_orchestrator_label
    }'
  exit 0
fi

emit_kv() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "${key}" "${value}"
}

emit_kv "requested_main" "${requested_main}"
emit_kv "requested_assist" "${requested_assist}"
emit_kv "resolved_main" "${resolved_main}"
emit_kv "resolved_assist" "${resolved_assist}"
emit_kv "main_fallback_applied" "${main_fallback_applied}"
emit_kv "main_fallback_reason" "${main_fallback_reason}"
emit_kv "assist_fallback_applied" "${assist_fallback_applied}"
emit_kv "assist_fallback_reason" "${assist_fallback_reason}"
emit_kv "pressure_guard_applied" "${pressure_guard_applied}"
emit_kv "pressure_guard_reason" "${pressure_guard_reason}"
emit_kv "claude_role_policy" "${claude_role_policy}"
emit_kv "degraded_assist_policy" "${degraded_assist_policy}"
emit_kv "compat_label" "${compat_label}"
emit_kv "orchestrator_label" "${orchestrator_label}"
emit_kv "assist_orchestrator_label" "${assist_orchestrator_label}"
