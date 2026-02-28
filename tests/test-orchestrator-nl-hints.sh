#!/usr/bin/env bash
set -euo pipefail

# test-orchestrator-nl-hints.sh — Unit test for NL hint parser.
#
# Tests key NL inference patterns: directives, questions, negations,
# pair intents, single-mode, and edge cases.
#
# Usage: bash tests/test-orchestrator-nl-hints.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
NL="${SCRIPT_DIR}/scripts/lib/orchestrator-nl-hints.sh"

passed=0
failed=0
total=0

assert_nl() {
  local test_name="$1"
  shift
  local expected_main="$1" expected_assist="$2" expected_applied="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${NL}" "$@" --format env)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"

  local errors=""
  if [[ "${nl_main_hint}" != "${expected_main}" ]]; then
    errors+=" main=${nl_main_hint}(expected ${expected_main})"
  fi
  if [[ "${nl_assist_hint}" != "${expected_assist}" ]]; then
    errors+=" assist=${nl_assist_hint}(expected ${expected_assist})"
  fi
  if [[ "${nl_hint_applied}" != "${expected_applied}" ]]; then
    errors+=" applied=${nl_hint_applied}(expected ${expected_applied})"
  fi

  if [[ -n "${errors}" ]]; then
    echo "FAIL [${test_name}]:${errors}"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

echo "=== orchestrator-nl-hints.sh unit tests ==="
echo ""

# --- Group 1: Question detection (should skip inference) ---
assert_nl "question-ja" \
  "" "" "false" \
  --text "claudeをmainにできますか？"

assert_nl "question-mark" \
  "" "" "false" \
  --text "can we use claude as main?"

assert_nl "question-desuka" \
  "" "" "false" \
  --text "claudeはmainですか"

# --- Group 2: Directive pair intent ---
assert_nl "pair-claude-main-codex-sub" \
  "claude" "codex" "true" \
  --text "claudeをmainにして、codexをsubにして"

assert_nl "pair-codex-main-claude-sub" \
  "codex" "claude" "true" \
  --text "codexがmainでclaudeがsub"

assert_nl "pair-en-claude-main" \
  "claude" "codex" "true" \
  --text "set claude as main orchestrator with codex as co-orchestrator"

assert_nl "pair-en-codex-main" \
  "codex" "claude" "true" \
  --text "switch to codex main orchestrator and claude assist"

# --- Group 3: Negation patterns ---
assert_nl "negate-claude-main" \
  "codex" "" "true" \
  --text "claudeを使わないでcodexにして"

assert_nl "negate-codex-main" \
  "claude" "" "true" \
  --text "codex禁止、claudeにする"

assert_nl "negate-claude-assist" \
  "" "none" "true" \
  --text "サブのclaude使わない"

# --- Group 4: Single-mode ---
assert_nl "codex-single-ja" \
  "codex" "none" "true" \
  --text "codex単独モードにして"

assert_nl "claude-single-en" \
  "claude" "none" "true" \
  --text "run claude single only"

assert_nl "codex-solo" \
  "codex" "none" "true" \
  --text "codex solo mode"

# --- Group 5: Rate-limit fallback pattern ---
assert_nl "rate-limit-codex-single" \
  "codex" "none" "true" \
  --text "claude rate limit のため codex 単独で実行"

assert_nl "rate-limit-exhausted" \
  "codex" "none" "true" \
  --text "claude exhausted: codex single mode"

# --- Group 6: Main-only hints ---
assert_nl "main-claude-only" \
  "claude" "" "true" \
  --text "main orchestrator claude にして"

assert_nl "main-codex-only" \
  "codex" "" "true" \
  --text "codexをmainにする"

# --- Group 7: Assist-only hints ---
assert_nl "assist-none" \
  "" "none" "true" \
  --text "assist なしで実行"

assert_nl "assist-claude" \
  "" "claude" "true" \
  --text "subにclaudeを設定して"

assert_nl "assist-codex" \
  "" "codex" "true" \
  --text "codexをsubにして"

# --- Group 8: No hint (neutral text) ---
assert_nl "neutral-text" \
  "" "" "false" \
  --text "テストを実行してください"

assert_nl "empty-text" \
  "" "" "false" \
  --text ""

# --- Group 9: Question with directive (directive wins) ---
assert_nl "question-with-directive" \
  "claude" "codex" "true" \
  --text "claudeをmainにしてcodexをsubにして？"

# --- Group 10: Title + body combination ---
assert_nl "title-body-combined" \
  "claude" "" "true" \
  --title "claudeをmainにする" \
  --body "詳細な設定について"

# --- Group 11: Case insensitivity ---
assert_nl "uppercase-providers" \
  "claude" "codex" "true" \
  --text "CLAUDEをMAINにしてCODEXをSUBにする"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
exit 0
