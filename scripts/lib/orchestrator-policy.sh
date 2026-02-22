#!/usr/bin/env bash
set -euo pipefail

# Resolve per-issue orchestrator policy with shared fallback/pressure guards.
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

resolved_main="${requested_main}"
resolved_assist="${requested_assist}"

main_fallback_applied="false"
main_fallback_reason=""
if [[ "${resolved_main}" == "claude" && "${claude_state}" != "ok" && "${force_claude}" != "true" ]]; then
  resolved_main="codex"
  main_fallback_applied="true"
  main_fallback_reason="claude-rate-limit-${claude_state}"
fi

assist_fallback_applied="false"
assist_fallback_reason=""
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
      compat_label:$compat_label,
      orchestrator_label:$orchestrator_label,
      assist_orchestrator_label:$assist_orchestrator_label
    }'
  exit 0
fi

cat <<EOF
requested_main=${requested_main}
requested_assist=${requested_assist}
resolved_main=${resolved_main}
resolved_assist=${resolved_assist}
main_fallback_applied=${main_fallback_applied}
main_fallback_reason=${main_fallback_reason}
assist_fallback_applied=${assist_fallback_applied}
assist_fallback_reason=${assist_fallback_reason}
pressure_guard_applied=${pressure_guard_applied}
pressure_guard_reason=${pressure_guard_reason}
compat_label=${compat_label}
orchestrator_label=${orchestrator_label}
assist_orchestrator_label=${assist_orchestrator_label}
EOF
