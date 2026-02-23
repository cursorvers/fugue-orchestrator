#!/usr/bin/env bash
set -euo pipefail

# Infer orchestrator hints from free-form text.
# Output: shell assignments suitable for eval.
#
# Example:
#   eval "$(
#     scripts/lib/orchestrator-nl-hints.sh \
#       --title "claudeをmainに、codexをsubにして" \
#       --body "..."
#   )"

title=""
body=""
text=""
format="env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      title="${2:-}"
      shift 2
      ;;
    --body)
      body="${2:-}"
      shift 2
      ;;
    --text)
      text="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-env}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: orchestrator-nl-hints.sh [options]

Options:
  --title VALUE     Optional title text to parse
  --body VALUE      Optional body text to parse
  --text VALUE      Optional free-form text to parse
  --format VALUE    env (default) or json
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${text}" ]]; then
  text="$(printf '%s\n%s\n' "${title}" "${body}")"
fi

flat="$(printf '%s' "${text}" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"

nl_main_hint=""
nl_assist_hint=""
nl_main_reason=""
nl_assist_reason=""
nl_inference_skipped_reason=""

contains() {
  local pattern="$1"
  printf '%s\n' "${flat}" | grep -Eqi "${pattern}"
}

question_like="false"
if contains '(\?|？|なのか|ですか|できますか|可能ですか)'; then
  question_like="true"
fi
directive_like="false"
if contains '(にして|にする|切り替|switch|set|使って|使う|運用|設定|固定|発動|有効|無効|disable|enable|使わない|しないで)'; then
  directive_like="true"
fi

if [[ "${question_like}" == "true" && "${directive_like}" != "true" ]]; then
  nl_inference_skipped_reason="question-without-directive"
else
  # Negative intent first to avoid false positives on plain mention.
  if contains 'claude.{0,24}(しない|使わない|不要|やめ|禁止|off|disable|ではない|じゃない|not)' && contains 'codex'; then
    nl_main_hint="codex"
    nl_main_reason="negate-claude-main"
  elif contains 'codex.{0,24}(しない|使わない|不要|やめ|禁止|off|disable|ではない|じゃない|not)' && contains 'claude'; then
    nl_main_hint="claude"
    nl_main_reason="negate-codex-main"
  fi

  if contains '(assist|sub|co-?orchestrator|サブ).{0,24}claude.{0,24}(しない|使わない|不要|やめ|禁止|off|disable|ではない|じゃない|not)|claude.{0,24}(assist|sub|co-?orchestrator|サブ).{0,24}(しない|使わない|不要|やめ|禁止|off|disable|ではない|じゃない|not)'; then
    if contains 'codex'; then
      nl_assist_hint="codex"
      nl_assist_reason="negate-claude-assist->codex"
    else
      nl_assist_hint="none"
      nl_assist_reason="negate-claude-assist->none"
    fi
  elif contains '(assist|sub|co-?orchestrator|サブ).{0,24}codex.{0,24}(しない|使わない|不要|やめ|禁止|off|disable|ではない|じゃない|not)|codex.{0,24}(assist|sub|co-?orchestrator|サブ).{0,24}(しない|使わない|不要|やめ|禁止|off|disable|ではない|じゃない|not)'; then
    if contains 'claude'; then
      nl_assist_hint="claude"
      nl_assist_reason="negate-codex-assist->claude"
    else
      nl_assist_hint="none"
      nl_assist_reason="negate-codex-assist->none"
    fi
  fi

  # Strong pair intent: rate-limit fallback to Codex single-mode.
  if [[ -z "${nl_main_hint}" && -z "${nl_assist_hint}" ]] && contains 'claude.{0,24}(rate[[:space:]_-]*limit|degraded|exhausted|制限|上限|枯渇).{0,48}codex.{0,24}(単独|single|solo|only)'; then
    nl_main_hint="codex"
    nl_assist_hint="none"
    nl_main_reason="claude-rate-limit-codex-single"
    nl_assist_reason="claude-rate-limit-codex-single"
  fi

  # Pair intent: Claude main + Codex sub/co-assist.
  if [[ -z "${nl_main_hint}" && -z "${nl_assist_hint}" ]] && contains '(claude.{0,28}(main[[:space:]_-]*orchestrator|main|メイン).{0,40}codex.{0,28}(assist|sub|co-?orchestrator|サブ)|codex.{0,28}(assist|sub|co-?orchestrator|サブ).{0,40}claude.{0,28}(main[[:space:]_-]*orchestrator|main|メイン)|claudeがmain.{0,28}codexが(sub|assist))'; then
    nl_main_hint="claude"
    nl_assist_hint="codex"
    nl_main_reason="claude-main-codex-sub"
    nl_assist_reason="claude-main-codex-sub"
  fi

  # Pair intent: Codex main + Claude sub/co-assist.
  if [[ -z "${nl_main_hint}" && -z "${nl_assist_hint}" ]] && contains '(codex.{0,28}(main[[:space:]_-]*orchestrator|main|メイン).{0,40}claude.{0,28}(assist|sub|co-?orchestrator|サブ)|claude.{0,28}(assist|sub|co-?orchestrator|サブ).{0,40}codex.{0,28}(main[[:space:]_-]*orchestrator|main|メイン)|codexがmain.{0,28}claudeが(sub|assist))'; then
    nl_main_hint="codex"
    nl_assist_hint="claude"
    nl_main_reason="codex-main-claude-sub"
    nl_assist_reason="codex-main-claude-sub"
  fi

  # Main-only hint.
  if [[ -z "${nl_main_hint}" ]]; then
    if contains '(main[[:space:]_-]*orchestrator.{0,16}claude|claude.{0,16}main[[:space:]_-]*orchestrator|claudeがmain|メイン[[:space:]]*orchestrator.{0,16}claude)'; then
      nl_main_hint="claude"
      nl_main_reason="main-claude"
    elif contains '(main[[:space:]_-]*orchestrator.{0,16}codex|codex.{0,16}main[[:space:]_-]*orchestrator|codexがmain|メイン[[:space:]]*orchestrator.{0,16}codex)'; then
      nl_main_hint="codex"
      nl_main_reason="main-codex"
    fi
  fi

  # Assist-only hint.
  if [[ -z "${nl_assist_hint}" ]]; then
    if contains '(assist|sub|co-?orchestrator|サブ).{0,20}(none|なし|無効|off|停止)|assistなし'; then
      nl_assist_hint="none"
      nl_assist_reason="assist-none"
    elif contains '(assist|sub|co-?orchestrator|サブ).{0,20}claude|claude.{0,20}(assist|sub|co-?orchestrator|サブ)|claudeをsub'; then
      nl_assist_hint="claude"
      nl_assist_reason="assist-claude"
    elif contains '(assist|sub|co-?orchestrator|サブ).{0,20}codex|codex.{0,20}(assist|sub|co-?orchestrator|サブ)|codexをsub'; then
      nl_assist_hint="codex"
      nl_assist_reason="assist-codex"
    fi
  fi

  # Single-mode hints when pair intent was not already captured.
  if [[ -z "${nl_main_hint}" && -z "${nl_assist_hint}" ]] && contains 'codex.{0,20}(単独|single|solo|only)'; then
    nl_main_hint="codex"
    nl_assist_hint="none"
    nl_main_reason="codex-single"
    nl_assist_reason="codex-single"
  fi
  if [[ -z "${nl_main_hint}" && -z "${nl_assist_hint}" ]] && contains 'claude.{0,20}(単独|single|solo|only)'; then
    nl_main_hint="claude"
    nl_assist_hint="none"
    nl_main_reason="claude-single"
    nl_assist_reason="claude-single"
  fi
fi

if [[ "${nl_main_hint}" != "claude" && "${nl_main_hint}" != "codex" ]]; then
  nl_main_hint=""
  nl_main_reason=""
fi
if [[ "${nl_assist_hint}" != "claude" && "${nl_assist_hint}" != "codex" && "${nl_assist_hint}" != "none" ]]; then
  nl_assist_hint=""
  nl_assist_reason=""
fi

nl_hint_applied="false"
if [[ -n "${nl_main_hint}" || -n "${nl_assist_hint}" ]]; then
  nl_hint_applied="true"
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg nl_main_hint "${nl_main_hint}" \
    --arg nl_assist_hint "${nl_assist_hint}" \
    --arg nl_main_reason "${nl_main_reason}" \
    --arg nl_assist_reason "${nl_assist_reason}" \
    --arg nl_inference_skipped_reason "${nl_inference_skipped_reason}" \
    --arg nl_hint_applied "${nl_hint_applied}" \
    '{
      nl_main_hint: $nl_main_hint,
      nl_assist_hint: $nl_assist_hint,
      nl_main_reason: $nl_main_reason,
      nl_assist_reason: $nl_assist_reason,
      nl_inference_skipped_reason: $nl_inference_skipped_reason,
      nl_hint_applied: ($nl_hint_applied == "true")
    }'
else
  printf 'nl_main_hint=%q\n' "${nl_main_hint}"
  printf 'nl_assist_hint=%q\n' "${nl_assist_hint}"
  printf 'nl_main_reason=%q\n' "${nl_main_reason}"
  printf 'nl_assist_reason=%q\n' "${nl_assist_reason}"
  printf 'nl_inference_skipped_reason=%q\n' "${nl_inference_skipped_reason}"
  printf 'nl_hint_applied=%q\n' "${nl_hint_applied}"
fi
