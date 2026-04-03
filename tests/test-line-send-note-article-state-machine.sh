#!/usr/bin/env bash
set -euo pipefail

passed=0
failed=0

resolve_mode() {
  local pending_state="$1"
  local pending_age="$2"
  local ttl="$3"
  local article_notified="$4"

  if [[ -n "${pending_state}" ]]; then
    if (( pending_age >= 0 && pending_age < ttl )); then
      if [[ "${pending_state}" == "accepted" ]]; then
        if [[ "${article_notified}" == "false" ]]; then
          printf '%s' "reconcile"
          return 0
        fi
        printf '%s' "clear-and-continue"
        return 0
      fi
      printf '%s' "prepared-skip"
      return 0
    fi
    printf '%s' "stale-clear"
    return 0
  fi
  printf '%s' "fresh-send"
}

assert_mode() {
  local name="$1"
  local expected="$2"
  shift 2
  local actual
  actual="$(resolve_mode "$@")"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "PASS [${name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${name}]: expected ${expected}, got ${actual}" >&2
    failed=$((failed + 1))
  fi
}

echo "=== line-send-note-article state machine simulation ==="
assert_mode "fresh-send-without-lock" "fresh-send" "" -1 21600 false
assert_mode "prepared-lock-blocks-retry-within-ttl" "prepared-skip" "prepared" 120 21600 false
assert_mode "accepted-lock-reconciles-without-resend" "reconcile" "accepted" 120 21600 false
assert_mode "accepted-lock-clears-when-db-already-updated" "clear-and-continue" "accepted" 120 21600 true
assert_mode "stale-lock-clears-after-ttl" "stale-clear" "prepared" 30000 21600 false

echo "=== Results: ${passed} passed, ${failed} failed ==="
if (( failed > 0 )); then
  exit 1
fi
