#!/usr/bin/env bash
set -euo pipefail

# Deterministic orchestration simulation.
# This does not call external APIs or mutate GitHub.

printf "scenario\trequested\tclaude_state\tforce_claude\tresolved\tmain\tsidecar\timpl_gate\tnote\n"

run_case() {
  local scenario="$1"
  local requested="$2"
  local claude_state="$3"
  local force_claude="$4"
  local mode="$5"
  local vote="$6"
  local high_risk="$7"
  local needs_sidecar="$8"

  local resolved="${requested}"
  if [[ "${resolved}" == "claude" && "${claude_state}" != "ok" && "${force_claude}" != "true" ]]; then
    resolved="codex"
  fi

  local main="codex"
  local sidecar="off"
  local impl_gate="no-implement"
  local note=""

  if [[ "${needs_sidecar}" == "yes" ]]; then
    if [[ "${claude_state}" == "ok" || "${force_claude}" == "true" ]]; then
      sidecar="claude"
    else
      sidecar="off"
      note="sidecar-skipped-throttle"
    fi
  fi

  if [[ "${mode}" == "implement" && "${vote}" == "pass" && "${high_risk}" == "false" ]]; then
    impl_gate="codex-implement"
  fi

  if [[ "${force_claude}" == "true" && "${claude_state}" != "ok" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}forced-claude-under-throttle"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${scenario}" \
    "${requested}" \
    "${claude_state}" \
    "${force_claude}" \
    "${resolved}" \
    "${main}" \
    "${sidecar}" \
    "${impl_gate}" \
    "${note}"
}

run_case "S1" "codex"  "ok"        "false" "review"    "pass"   "false" "yes"
run_case "S2" "claude" "ok"        "false" "implement" "pass"   "false" "yes"
run_case "S3" "claude" "degraded"  "false" "review"    "pass"   "false" "yes"
run_case "S4" "claude" "exhausted" "false" "implement" "pass"   "false" "yes"
run_case "S5" "claude" "exhausted" "true"  "review"    "pass"   "false" "yes"
run_case "S6" "claude" "ok"        "false" "implement" "pass"   "true"  "yes"
run_case "S7" "claude" "ok"        "false" "implement" "reject" "false" "yes"
run_case "S8" "codex"  "ok"        "false" "implement" "pass"   "false" "no"
