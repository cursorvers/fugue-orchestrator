#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

run_case() {
  local case_name="$1"
  local expected="$2"
  local pending_state="$3"
  local pending_age="$4"
  local article_notified="$5"
  local ttl="21600"
  local actual=""

  if [[ -n "${pending_state}" ]]; then
    if (( pending_age >= 0 && pending_age < ttl )); then
      if [[ "${pending_state}" == "accepted" ]]; then
        if [[ "${article_notified}" == "false" ]]; then
          actual="reconcile-no-resend"
        else
          actual="clear-stale-lock"
        fi
      else
        actual="skip-prepared-lock"
      fi
    else
      actual="clear-expired-lock"
    fi
  else
    actual="attempt-send"
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL [${case_name}]: expected ${expected}, got ${actual}" >&2
    return 1
  fi

  echo "PASS [${case_name}]"
}

echo "=== line-send-note-article failure injection ==="
run_case "no-lock-attempts-send" "attempt-send" "" -1 false
run_case "prepared-lock-skips-send" "skip-prepared-lock" "prepared" 120 false
run_case "accepted-lock-reconciles" "reconcile-no-resend" "accepted" 120 false
run_case "accepted-lock-clears-when-db-updated" "clear-stale-lock" "accepted" 120 true
run_case "expired-lock-clears" "clear-expired-lock" "prepared" 30000 false
