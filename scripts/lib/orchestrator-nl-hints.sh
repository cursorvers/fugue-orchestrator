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
workspace_action_hint=""
workspace_domain_hint=""
workspace_reason=""
workspace_hint_applied="false"
content_action_hint=""
content_skill_hint=""
content_reason=""
content_hint_applied="false"

contains() {
  local pattern="$1"
  printf '%s\n' "${flat}" | grep -Eqi "${pattern}"
}

append_csv_unique() {
  local current="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    printf '%s' "${current}"
    return 0
  fi
  case ",${current}," in
    *,"${value}",*)
      printf '%s' "${current}"
      ;;
    *)
      if [[ -z "${current}" ]]; then
        printf '%s' "${value}"
      else
        printf '%s,%s' "${current}" "${value}"
      fi
      ;;
  esac
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
    if contains '(main[[:space:]_-]*orchestrator.{0,16}claude|claude.{0,16}main[[:space:]_-]*orchestrator|claude[をが].{0,4}main|claude as main|メイン[[:space:]]*orchestrator.{0,16}claude)'; then
      nl_main_hint="claude"
      nl_main_reason="main-claude"
    elif contains '(main[[:space:]_-]*orchestrator.{0,16}codex|codex.{0,16}main[[:space:]_-]*orchestrator|codex[をが].{0,4}main|codex as main|メイン[[:space:]]*orchestrator.{0,16}codex)'; then
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

if contains '(meeting[[:space:]_-]*prep|meeting|calendar|agenda|attendee|会議|打ち合わせ|予定|アジェンダ|参加者)'; then
  workspace_action_hint="$(append_csv_unique "${workspace_action_hint}" "meeting-prep")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "calendar")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "drive")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "docs")"
  workspace_reason="$(append_csv_unique "${workspace_reason}" "meeting-context")"
fi

if contains '(standup|daily[[:space:]_-]*report|daily[[:space:]_-]*brief|朝会|日報|スタンドアップ)'; then
  workspace_action_hint="$(append_csv_unique "${workspace_action_hint}" "standup-report")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "calendar")"
  workspace_reason="$(append_csv_unique "${workspace_reason}" "standup-context")"
fi

if contains '(weekly[[:space:]_-]*digest|週次|週報|digest|ダイジェスト)'; then
  workspace_action_hint="$(append_csv_unique "${workspace_action_hint}" "weekly-digest")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "calendar")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "gmail")"
  workspace_reason="$(append_csv_unique "${workspace_reason}" "digest-context")"
fi

if contains '(gmail|email|e-mail|mail|inbox|受信箱|未読|メール|triage|トリアージ)'; then
  workspace_action_hint="$(append_csv_unique "${workspace_action_hint}" "gmail-triage")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "gmail")"
  workspace_reason="$(append_csv_unique "${workspace_reason}" "mail-context")"
fi

if contains '(drive|folder|file|files|document|docs|doc|資料|添付|共有ファイル|共有資料)'; then
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "drive")"
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "docs")"
  workspace_reason="$(append_csv_unique "${workspace_reason}" "document-context")"
fi

if contains '(sheet|sheets|spreadsheet|スプレッドシート|表計算|csv|table|レポート表)'; then
  workspace_domain_hint="$(append_csv_unique "${workspace_domain_hint}" "sheets")"
  workspace_reason="$(append_csv_unique "${workspace_reason}" "sheet-context")"
fi

if [[ -n "${workspace_action_hint}" || -n "${workspace_domain_hint}" ]]; then
  workspace_hint_applied="true"
fi

note_negated="false"
if contains '(note\.com|note記事|note向け|note 用|noteを書|原稿|manuscript).{0,12}(ではなく|じゃなく|ではない|じゃない|not)'; then
  note_negated="true"
fi

if contains '(slide|slides|deck|pptx|presentation|プレゼン|スライド|資料作成)'; then
  content_action_hint="$(append_csv_unique "${content_action_hint}" "slide-deck")"
  content_skill_hint="$(append_csv_unique "${content_skill_hint}" "slide")"
  content_reason="$(append_csv_unique "${content_reason}" "slide-request")"
fi

if contains '(company profile|company intro|company introduction|company overview|corporate deck|sales deck|会社紹介|企業紹介|会社概要|事業紹介)' \
  && contains '(slide|slides|deck|pptx|presentation|プレゼン|スライド|資料作成)'; then
  content_action_hint="$(append_csv_unique "${content_action_hint}" "company-deck")"
  content_reason="$(append_csv_unique "${content_reason}" "company-deck-request")"
fi

if contains '(academic|学術|学会|研究発表|講義資料)' && contains '(slide|slides|deck|pptx|presentation|プレゼン|スライド)'; then
  content_action_hint="$(append_csv_unique "${content_action_hint}" "academic-slide")"
  content_skill_hint="$(append_csv_unique "${content_skill_hint}" "academic-two-stage-slide")"
  content_reason="$(append_csv_unique "${content_reason}" "academic-slide-request")"
fi

if [[ "${note_negated}" != "true" ]] && contains '(note\.com|note記事|note向け|note 用|noteを書|原稿|manuscript|長文記事|記事を書いて|記事にして|note に)'; then
  content_action_hint="$(append_csv_unique "${content_action_hint}" "note-manuscript")"
  content_skill_hint="$(append_csv_unique "${content_skill_hint}" "note-manuscript")"
  content_reason="$(append_csv_unique "${content_reason}" "note-request")"
fi

if [[ -n "${content_action_hint}" || -n "${content_skill_hint}" ]]; then
  content_hint_applied="true"
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
    --arg workspace_action_hint "${workspace_action_hint}" \
    --arg workspace_domain_hint "${workspace_domain_hint}" \
    --arg workspace_reason "${workspace_reason}" \
    --arg workspace_hint_applied "${workspace_hint_applied}" \
    --arg content_action_hint "${content_action_hint}" \
    --arg content_skill_hint "${content_skill_hint}" \
    --arg content_reason "${content_reason}" \
    --arg content_hint_applied "${content_hint_applied}" \
    '{
      nl_main_hint: $nl_main_hint,
      nl_assist_hint: $nl_assist_hint,
      nl_main_reason: $nl_main_reason,
      nl_assist_reason: $nl_assist_reason,
      nl_inference_skipped_reason: $nl_inference_skipped_reason,
      nl_hint_applied: ($nl_hint_applied == "true"),
      workspace_action_hint: $workspace_action_hint,
      workspace_domain_hint: $workspace_domain_hint,
      workspace_reason: $workspace_reason,
      workspace_hint_applied: ($workspace_hint_applied == "true"),
      content_action_hint: $content_action_hint,
      content_skill_hint: $content_skill_hint,
      content_reason: $content_reason,
      content_hint_applied: ($content_hint_applied == "true")
    }'
else
  printf 'nl_main_hint=%q\n' "${nl_main_hint}"
  printf 'nl_assist_hint=%q\n' "${nl_assist_hint}"
  printf 'nl_main_reason=%q\n' "${nl_main_reason}"
  printf 'nl_assist_reason=%q\n' "${nl_assist_reason}"
  printf 'nl_inference_skipped_reason=%q\n' "${nl_inference_skipped_reason}"
  printf 'nl_hint_applied=%q\n' "${nl_hint_applied}"
  printf 'workspace_action_hint=%q\n' "${workspace_action_hint}"
  printf 'workspace_domain_hint=%q\n' "${workspace_domain_hint}"
  printf 'workspace_reason=%q\n' "${workspace_reason}"
  printf 'workspace_hint_applied=%q\n' "${workspace_hint_applied}"
  printf 'content_action_hint=%q\n' "${content_action_hint}"
  printf 'content_skill_hint=%q\n' "${content_skill_hint}"
  printf 'content_reason=%q\n' "${content_reason}"
  printf 'content_hint_applied=%q\n' "${content_hint_applied}"
fi
