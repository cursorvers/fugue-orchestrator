#!/usr/bin/env bash
set -euo pipefail

# Deterministic orchestration simulation.
# This does not call external APIs or mutate GitHub.

printf "scenario\trequested_main\trequested_assist\tclaude_state\tforce_claude\tresolved_main\tresolved_assist\timpl_gate\tnote\n"

run_case() {
  local scenario="$1"
  local requested_main="$2"
  local requested_assist="$3"
  local claude_state="$4"
  local force_claude="$5"
  local mode="$6"
  local vote="$7"
  local high_risk="$8"

  local resolved_main="${requested_main}"
  if [[ "${resolved_main}" == "claude" && "${claude_state}" != "ok" && "${force_claude}" != "true" ]]; then
    resolved_main="codex"
  fi

  local resolved_assist="${requested_assist}"
  if [[ "${resolved_assist}" == "claude" && "${claude_state}" == "exhausted" && "${force_claude}" != "true" ]]; then
    resolved_assist="none"
  fi

  local impl_gate="no-implement"
  local note=""

  if [[ "${mode}" == "implement" && "${vote}" == "pass" && "${high_risk}" == "false" ]]; then
    impl_gate="codex-implement"
  fi

  if [[ "${requested_main}" == "claude" && "${resolved_main}" == "codex" ]]; then
    note="main-fallback-claude-to-codex"
  fi
  if [[ "${requested_assist}" == "claude" && "${resolved_assist}" == "none" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}assist-fallback-claude-to-none"
  fi
  if [[ "${force_claude}" == "true" && "${claude_state}" != "ok" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}forced-claude-under-throttle"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${scenario}" \
    "${requested_main}" \
    "${requested_assist}" \
    "${claude_state}" \
    "${force_claude}" \
    "${resolved_main}" \
    "${resolved_assist}" \
    "${impl_gate}" \
    "${note}"
}

run_case "S1"  "codex"  "claude" "ok"        "false" "review"    "pass"   "false"
run_case "S2"  "claude" "claude" "ok"        "false" "implement" "pass"   "false"
run_case "S3"  "claude" "claude" "degraded"  "false" "review"    "pass"   "false"
run_case "S4"  "claude" "claude" "exhausted" "false" "implement" "pass"   "false"
run_case "S5"  "claude" "claude" "exhausted" "true"  "review"    "pass"   "false"
run_case "S6"  "claude" "none"   "ok"        "false" "implement" "pass"   "true"
run_case "S7"  "codex"  "codex"  "ok"        "false" "implement" "reject" "false"
run_case "S8"  "codex"  "claude" "ok"        "false" "implement" "pass"   "false"
