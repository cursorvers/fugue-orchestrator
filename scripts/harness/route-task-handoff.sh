#!/usr/bin/env bash
set -euo pipefail

# route-task-handoff.sh — Parse issue context and hand off to Tutti Mainframe.
#
# Extracts provider hints, mode, risk tier from issue title/body/comment,
# generates handoff comment, labels the issue, and dispatches
# fugue-tutti-caller.yml.
#
# Required env vars: GH_TOKEN, ISSUE_NUMBER, ISSUE_TITLE, ISSUE_BODY,
#   COMMENT_BODY, IS_VOTE_COMMAND, VOTE_INSTRUCTION, TRUST_SUBJECT,
#   DEFAULT_MAIN_ORCHESTRATOR_PROVIDER, DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER,
#   CLAUDE_RATE_LIMIT_STATE, CLAUDE_MAIN_ASSIST_POLICY, CLAUDE_ROLE_POLICY,
#   CLAUDE_DEGRADED_ASSIST_POLICY
#
# Usage: bash scripts/harness/route-task-handoff.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common-utils.sh"

title="${ISSUE_TITLE}"
body="${ISSUE_BODY}"
comment="${COMMENT_BODY}"
vote_instruction="$(printf '%s' "${VOTE_INSTRUCTION:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
allow_processing_rerun_input="$(printf '%s' "${ALLOW_PROCESSING_RERUN_INPUT:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${allow_processing_rerun_input}" != "true" ]]; then
  allow_processing_rerun_input="false"
fi
subscription_offline_policy_override="$(printf '%s' "${SUBSCRIPTION_OFFLINE_POLICY_OVERRIDE_INPUT:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${subscription_offline_policy_override}" != "hold" && "${subscription_offline_policy_override}" != "continuity" ]]; then
  subscription_offline_policy_override=""
fi
handoff_target_input="$(printf '%s' "${HANDOFF_TARGET_INPUT:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${handoff_target_input}" != "kernel" && "${handoff_target_input}" != "fugue-bridge" ]]; then
  handoff_target_input=""
fi
kernel_run_id_input="$(printf '%s' "${KERNEL_RUN_ID_INPUT:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
execution_mode_override="$(printf '%s' "${EXECUTION_MODE_OVERRIDE_INPUT:-auto}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${execution_mode_override}" in
  auto|primary|backup-safe|backup-heavy) ;;
  *) execution_mode_override="auto" ;;
esac
resolved_execution_mode_override="${execution_mode_override}"
if [[ "${resolved_execution_mode_override}" == "auto" && "${IS_VOTE_COMMAND}" == "true" ]]; then
  resolved_execution_mode_override="primary"
fi
if [[ "${IS_VOTE_COMMAND}" == "true" ]]; then
  # Keep structured parsing immune to comment-injected headings.
  text="$(printf '%s\n%s\n' "${title}" "${body}")"
else
  text="$(printf '%s\n%s\n%s\n' "${title}" "${body}" "${comment}")"
fi
mode_text="${text}"
if [[ -n "${vote_instruction}" ]]; then
  # Accept plain-text mode overrides from `/vote ...` without trusting
  # arbitrary headings injected in the comment body.
  mode_text="$(printf '%s\n%s\n' "${mode_text}" "${vote_instruction}")"
fi

extract_heading_value() {
  local source="$1"
  local heading="$2"
  printf '%s\n' "${source}" | awk -v heading="${heading}" '
    BEGIN { in_sec=0; h=tolower(heading) }
    {
      raw=$0
      line=tolower($0)
      if (line ~ "^#{2,3}[[:space:]]*" h "[[:space:]]*$") { in_sec=1; next }
      if (in_sec && line ~ "^#{2,3}[[:space:]]+") { exit }
      if (in_sec) {
        gsub(/`/, "", raw)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
        if (raw != "") {
          print tolower(raw)
          exit
        }
      }
    }
  '
}

issue_json="$(fugue_gh_api_retry "repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}" 5)"
label_main_provider="$(echo "${issue_json}" | jq -r '
  [ .labels[]? | .name ] as $labels
  | if ((($labels | index("orchestrator:claude")) != null) and (($labels | index("orchestrator:codex")) != null)) then ""
    elif (($labels | index("orchestrator:claude")) != null) then "claude"
    elif (($labels | index("orchestrator:codex")) != null) then "codex"
    else "" end
')"
label_assist_provider="$(echo "${issue_json}" | jq -r '
  [ .labels[]? | .name ] as $labels
  | if (($labels | index("orchestrator-assist:none")) != null) then "none"
    elif ((($labels | index("orchestrator-assist:claude")) != null) and (($labels | index("orchestrator-assist:codex")) != null)) then ""
    elif (($labels | index("orchestrator-assist:claude")) != null) then "claude"
    elif (($labels | index("orchestrator-assist:codex")) != null) then "codex"
    else "" end
')"
force_claude="$(echo "${issue_json}" | jq -r '
  [ .labels[]? | .name ] | index("orchestrator-force:claude") != null
')"
has_confirm_label="$(echo "${issue_json}" | jq -r '[ .labels[]? | .name ] | index("implement-confirmed") != null')"

body_main_provider="$(extract_heading_value "${body}" "main orchestrator provider")"
if [[ -z "${body_main_provider}" ]]; then
  body_main_provider="$(extract_heading_value "${body}" "orchestrator provider")"
fi
if [[ "${body_main_provider}" != "claude" && "${body_main_provider}" != "codex" ]]; then
  body_main_provider=""
fi
if [[ -z "${body_main_provider}" ]]; then
  body_main_provider="$(echo "${body}" | sed -nE 's/^[[:space:]]*orchestrator[[:space:]_-]*provider[[:space:]]*:[[:space:]]*(claude|codex)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi

body_assist_provider="$(extract_heading_value "${body}" "assist orchestrator provider")"
if [[ "${body_assist_provider}" != "claude" && "${body_assist_provider}" != "codex" && "${body_assist_provider}" != "none" ]]; then
  body_assist_provider=""
fi
if [[ -z "${body_assist_provider}" ]]; then
  body_assist_provider="$(echo "${body}" | sed -nE 's/^[[:space:]]*assist[[:space:]]+orchestrator[[:space:]_-]*provider[[:space:]]*:[[:space:]]*(claude|codex|none)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi

orchestrator_lib_dir="scripts/lib"
if [[ ! -d "${orchestrator_lib_dir}" ]]; then
  orchestrator_lib_dir=".fugue-orchestrator/scripts/lib"
fi

nl_main_hint=""
nl_assist_hint=""
nl_hint_applied="false"
nl_inference_skipped_reason=""
if [[ -f "${orchestrator_lib_dir}/orchestrator-nl-hints.sh" ]]; then
  eval "$(
    bash "${orchestrator_lib_dir}/orchestrator-nl-hints.sh" \
      --title "${title}" \
      --body "${body}"
  )"
else
  nl_inference_skipped_reason="missing-orchestrator-nl-hints-script"
fi

provider="${label_main_provider}"
main_provider_source="label"
if [[ -z "${provider}" && -n "${body_main_provider}" ]]; then
  provider="${body_main_provider}"
  main_provider_source="body-structured"
fi
if [[ -z "${provider}" && -n "${nl_main_hint}" ]]; then
  provider="${nl_main_hint}"
  main_provider_source="body-natural-language"
fi
if [[ -z "${provider}" ]]; then
  main_provider_source="default"
fi
assist_provider="${label_assist_provider}"
assist_provider_source="label"
if [[ -z "${assist_provider}" && -n "${body_assist_provider}" ]]; then
  assist_provider="${body_assist_provider}"
  assist_provider_source="body-structured"
fi
if [[ -z "${assist_provider}" && -n "${nl_assist_hint}" ]]; then
  assist_provider="${nl_assist_hint}"
  assist_provider_source="body-natural-language"
fi
if [[ -z "${assist_provider}" ]]; then
  assist_provider_source="default"
fi

requested_main="${provider}"
requested_assist="${assist_provider}"
resolved_main="${provider:-${DEFAULT_MAIN_ORCHESTRATOR_PROVIDER}}"
resolved_assist="${assist_provider:-${DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER}}"
main_fallback_applied="false"
main_fallback_reason=""
assist_fallback_applied="false"
assist_fallback_reason=""
pressure_guard_applied="false"
pressure_guard_reason=""
if [[ -f "${orchestrator_lib_dir}/orchestrator-policy.sh" ]]; then
  eval "$(
    bash "${orchestrator_lib_dir}/orchestrator-policy.sh" \
      --main "${provider}" \
      --assist "${assist_provider}" \
      --default-main "${DEFAULT_MAIN_ORCHESTRATOR_PROVIDER}" \
      --default-assist "${DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER}" \
      --claude-state "${CLAUDE_RATE_LIMIT_STATE}" \
      --force-claude "${force_claude}" \
      --assist-policy "${CLAUDE_MAIN_ASSIST_POLICY}" \
      --claude-role-policy "${CLAUDE_ROLE_POLICY}" \
      --degraded-assist-policy "${CLAUDE_DEGRADED_ASSIST_POLICY}"
  )"
else
  main_fallback_reason="missing-orchestrator-policy-script"
fi
requested_provider="${requested_main}"
requested_assist_provider="${requested_assist}"
provider="${resolved_main}"
assist_provider="${resolved_assist}"
if [[ "${main_fallback_applied}" == "true" && -n "${main_fallback_reason}" ]]; then
  main_provider_source="${main_provider_source}+policy(${main_fallback_reason})"
fi
if [[ "${assist_fallback_applied}" == "true" && -n "${assist_fallback_reason}" ]]; then
  assist_provider_source="${assist_provider_source}+policy(${assist_fallback_reason})"
elif [[ "${pressure_guard_applied}" == "true" && -n "${pressure_guard_reason}" ]]; then
  assist_provider_source="${assist_provider_source}+policy(${pressure_guard_reason})"
fi

main_fallback_note=""
if [[ "${main_fallback_applied}" == "true" ]]; then
  main_fallback_note="Main orchestrator auto-fallback: requested \`${requested_provider}\` but switched to \`${provider}\` due to \`${main_fallback_reason}\`."
fi
assist_fallback_note=""
if [[ "${assist_fallback_applied}" == "true" ]]; then
  assist_fallback_note="Assist orchestrator auto-fallback: requested \`${requested_assist_provider}\` but switched to \`${assist_provider}\` due to \`${assist_fallback_reason}\`."
elif [[ "${pressure_guard_applied}" == "true" ]]; then
  assist_fallback_note="Assist orchestrator pressure guard: requested \`${requested_assist_provider}\` but switched to \`${assist_provider}\` due to \`${pressure_guard_reason}\`."
fi

handoff_target_default="$(echo "${FUGUE_HANDOFF_TARGET_DEFAULT:-kernel}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${handoff_target_default}" != "kernel" && "${handoff_target_default}" != "fugue-bridge" ]]; then
  handoff_target_default="kernel"
fi
body_handoff_target="$(extract_heading_value "${body}" "handoff target")"
if [[ -z "${body_handoff_target}" ]]; then
  body_handoff_target="$(extract_heading_value "${body}" "sovereign adapter")"
fi
if [[ "${body_handoff_target}" != "kernel" && "${body_handoff_target}" != "fugue-bridge" ]]; then
  body_handoff_target="$(echo "${body}" | sed -nE 's/^[[:space:]]*(handoff[[:space:]_-]*target|sovereign[[:space:]_-]*adapter)[[:space:]]*:[[:space:]]*(kernel|fugue-bridge)[[:space:]]*$/\2/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi
handoff_target="${handoff_target_default}"
if [[ "${body_handoff_target}" == "kernel" || "${body_handoff_target}" == "fugue-bridge" ]]; then
  handoff_target="${body_handoff_target}"
fi
if echo "${text}" | grep -Eqi '#fugue-bridge|rollback to fugue|legacy fugue'; then
  handoff_target="fugue-bridge"
elif echo "${text}" | grep -Eqi '#kernel'; then
  handoff_target="kernel"
fi

# Default: fugue-task issues are handed off to the GHA24 mainframe.
# Explicit manual markers can opt out, but /vote forces handoff.
body_mainframe_handoff="$(extract_heading_value "${body}" "mainframe handoff")"
wants_mainframe=true
if [[ "${body_mainframe_handoff}" == "manual" ]]; then
  wants_mainframe=false
fi
if echo "${text}" | grep -Eqi '(mainframeしない|自動実行しない|manual only|#manual|#no-gha24)'; then
  wants_mainframe=false
fi
if [[ "${IS_VOTE_COMMAND}" == "true" ]]; then
  wants_mainframe=true
fi

if [[ "${wants_mainframe}" != "true" ]]; then
  echo "handoff=false" >> "${GITHUB_OUTPUT}"
  exit 0
fi

# Mode selection:
# - Natural-language path defaults to review.
# - Explicit implement signal enters implement intent.
# - /vote defaults to implement unless review-only is explicit.
# - Explicit review-only always wins.
body_mode="$(extract_heading_value "${body}" "execution mode")"
if [[ "${body_mode}" != "implement" && "${body_mode}" != "review" ]]; then
  body_mode="$(extract_heading_value "${body}" "mode")"
fi
if [[ "${body_mode}" != "implement" && "${body_mode}" != "review" ]]; then
  body_mode="$(echo "${body}" | sed -nE 's/^[[:space:]]*execution[[:space:]_-]*mode[[:space:]]*:[[:space:]]*(implement|review)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi
if [[ "${body_mode}" != "implement" && "${body_mode}" != "review" ]]; then
  body_mode="$(echo "${body}" | sed -nE 's/^[[:space:]]*mode[[:space:]]*:[[:space:]]*(implement|review)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi
wants_review=false
wants_implement=false
if [[ "${body_mode}" == "implement" ]]; then
  wants_implement=true
elif echo "${mode_text}" | grep -Eqi '(#implement|implement mode|実装モード|実装して|実装まで|pr作成|pull request|完遂|最後まで)'; then
  wants_implement=true
fi
if [[ "${body_mode}" == "review" ]]; then
  wants_review=true
elif echo "${mode_text}" | grep -Eqi '(レビューのみ|指摘のみ|実装しない|実装不要|review only|no implement|no-implement|#review)'; then
  wants_review=true
fi
if [[ "${wants_review}" == "true" ]]; then
  wants_implement=false
elif [[ "${IS_VOTE_COMMAND}" == "true" ]]; then
  wants_implement=true
fi

body_implement_confirm="$(extract_heading_value "${body}" "implementation confirmation")"
if [[ "${body_implement_confirm}" != "confirmed" && "${body_implement_confirm}" != "pending" ]]; then
  body_implement_confirm="$(echo "${body}" | sed -nE 's/^[[:space:]]*implement(ation)?[[:space:]_-]*confirmation[[:space:]]*:[[:space:]]*(confirmed|pending)[[:space:]]*$/\2/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi
confirm_implement="${has_confirm_label}"
if [[ "${body_implement_confirm}" == "confirmed" ]]; then
  confirm_implement="true"
elif [[ "${body_implement_confirm}" == "pending" ]]; then
  confirm_implement="false"
fi
if echo "${text}" | grep -Eqi '(#confirm-implement|#impl-confirm|implement confirmed|実装確定)'; then
  confirm_implement="true"
fi
auto_confirmed_by_vote="false"
if [[ "${IS_VOTE_COMMAND}" == "true" && "${wants_implement}" == "true" && "${wants_review}" != "true" ]]; then
  confirm_implement="true"
  auto_confirmed_by_vote="true"
fi
if [[ "${wants_implement}" != "true" ]]; then
  confirm_implement="false"
  auto_confirmed_by_vote="false"
fi

# Safety guard: when review-only is explicitly requested, clear any
# stale implementation intent labels before handing off to Tutti.
if [[ "${wants_implement}" != "true" ]]; then
  fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" \
    --remove-label "implement" \
    --remove-label "codex-implement" \
    --remove-label "claude-implement" \
    --remove-label "implement-confirmed" >/dev/null 2>&1 || true
fi

# Prefer provider-agnostic implement intent label while also adding
# a provider-specific compatibility label for existing tooling.
if [[ "${wants_implement}" == "true" ]]; then
  # Keep only one compatibility label in sync with the resolved
  # orchestrator provider to avoid stale dual-label drift.
  fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" \
    --remove-label "codex-implement" \
    --remove-label "claude-implement" >/dev/null 2>&1 || true
  fugue_gh_retry 4 gh label create "implement" \
    --repo "${GITHUB_REPOSITORY}" \
    --description "Implementation intent (provider-agnostic)" \
    --color "1D76DB" >/dev/null 2>&1 || true
  fugue_gh_retry 4 gh label create "${compat_label}" \
    --repo "${GITHUB_REPOSITORY}" \
    --description "Implementation intent compatibility label" \
    --color "0052CC" >/dev/null 2>&1 || true
  fugue_gh_retry 4 gh label create "implement-confirmed" \
    --repo "${GITHUB_REPOSITORY}" \
    --description "Human has explicitly confirmed implementation execution" \
    --color "0E8A16" >/dev/null 2>&1 || true
  fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "implement" >/dev/null
  fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "${compat_label}" >/dev/null
  if [[ "${confirm_implement}" == "true" ]]; then
    fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "implement-confirmed" >/dev/null
  else
    fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --remove-label "implement-confirmed" >/dev/null 2>&1 || true
  fi
fi

fugue_gh_retry 4 gh label create "fugue-task" \
  --repo "${GITHUB_REPOSITORY}" \
  --description "FUGUE task routing target" \
  --color "5319E7" >/dev/null 2>&1 || true
fugue_gh_retry 4 gh label create "${orchestrator_label}" \
  --repo "${GITHUB_REPOSITORY}" \
  --description "Requested orchestrator profile for Tutti routing" \
  --color "5319E7" >/dev/null 2>&1 || true
fugue_gh_retry 4 gh label create "${assist_orchestrator_label}" \
  --repo "${GITHUB_REPOSITORY}" \
  --description "Requested assist orchestrator profile for Tutti routing" \
  --color "0052CC" >/dev/null 2>&1 || true
fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --remove-label "orchestrator:claude" --remove-label "orchestrator:codex" >/dev/null 2>&1 || true
fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --remove-label "orchestrator-assist:claude" --remove-label "orchestrator-assist:codex" --remove-label "orchestrator-assist:none" >/dev/null 2>&1 || true
fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --remove-label "content-task" --remove-label "content:slide" --remove-label "content:academic-slide" --remove-label "content:note" --remove-label "content-action:slide-deck" --remove-label "content-action:company-deck" --remove-label "content-action:academic-slide" --remove-label "content-action:note-manuscript" >/dev/null 2>&1 || true
fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "fugue-task" >/dev/null
fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "${orchestrator_label}" >/dev/null
fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "${assist_orchestrator_label}" >/dev/null

content_skill_label=""
content_action_label=""
if [[ "${content_hint_applied}" == "true" ]]; then
  fugue_gh_retry 4 gh label create "content-task" \
    --repo "${GITHUB_REPOSITORY}" \
    --description "Content-oriented task routed through Kernel/FUGUE" \
    --color "BFDADC" >/dev/null 2>&1 || true
  fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "content-task" >/dev/null || true
  case "${content_skill_hint}" in
    *academic-two-stage-slide*)
      content_skill_label="content:academic-slide"
      ;;
    *slide*)
      content_skill_label="content:slide"
      ;;
    *note-manuscript*)
      content_skill_label="content:note"
      ;;
  esac
  case "${content_action_hint}" in
    *academic-slide*)
      content_action_label="content-action:academic-slide"
      ;;
    *company-deck*)
      content_action_label="content-action:company-deck"
      ;;
    *slide-deck*)
      content_action_label="content-action:slide-deck"
      ;;
    *note-manuscript*)
      content_action_label="content-action:note-manuscript"
      ;;
  esac
  if [[ -n "${content_skill_label}" ]]; then
    fugue_gh_retry 4 gh label create "${content_skill_label}" \
      --repo "${GITHUB_REPOSITORY}" \
      --description "Content skill hint detected from natural language" \
      --color "C2E0C6" >/dev/null 2>&1 || true
    fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "${content_skill_label}" >/dev/null || true
  fi
  if [[ -n "${content_action_label}" ]]; then
    fugue_gh_retry 4 gh label create "${content_action_label}" \
      --repo "${GITHUB_REPOSITORY}" \
      --description "Content action hint detected from natural language" \
      --color "D4C5F9" >/dev/null 2>&1 || true
    fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "${content_action_label}" >/dev/null || true
  fi
fi

fugue_gh_retry 4 gh issue edit "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --add-label "tutti" >/dev/null

mode="$( [[ "${wants_implement}" == "true" ]] && echo "implement" || echo "review" )"
extra=""
confirmation_line="- Implement confirmation: not required (review mode)"
confirm_note=""
if [[ "${wants_implement}" == "true" ]]; then
  extra=" + implement (+ ${compat_label} compatibility)"
  if [[ "${confirm_implement}" == "true" ]]; then
    extra="${extra} + implement-confirmed"
    if [[ "${auto_confirmed_by_vote}" == "true" ]]; then
      confirmation_line="- Implement confirmation: auto-confirmed by \`/vote\`"
    else
      confirmation_line="- Implement confirmation: confirmed"
    fi
  else
    confirmation_line="- Implement confirmation: pending (\`implement-confirmed\` label required before execution)"
    confirm_note="Implementation intent is set, but execution is blocked until \`implement-confirmed\` is present."
  fi
fi
vote_instruction_line=""
vote_instruction_b64=""
if [[ "${IS_VOTE_COMMAND}" == "true" ]]; then
  if [[ -n "${vote_instruction}" ]]; then
    vote_instruction_line="- Vote instruction: accepted from \`/vote\` comment"
    vote_instruction_b64="$(printf '%s' "${vote_instruction}" | base64 | tr -d '\n')"
  else
    vote_instruction_line="- Vote instruction: none (command only)"
  fi
fi
intake_source="github-issue-handoff"
if [[ "${IS_VOTE_COMMAND}" == "true" ]]; then
  intake_source="github-vote-comment"
fi
provider_line="- Orchestrator: ${provider}"
if [[ -n "${main_fallback_note}" ]]; then
  provider_line="- Orchestrator: ${provider} (requested: ${requested_provider})"
fi
assist_provider_line="- Assist orchestrator: ${assist_provider}"
if [[ -n "${assist_fallback_note}" ]]; then
  assist_provider_line="- Assist orchestrator: ${assist_provider} (requested: ${requested_assist_provider})"
fi
handoff_target_line="- Handoff target: ${handoff_target}"
source_line="- Provider source: main=${main_provider_source}, assist=${assist_provider_source}"
nl_line=""
if [[ "${nl_hint_applied}" == "true" ]]; then
  nl_line="- Natural-language hints: main=${nl_main_hint:-none}, assist=${nl_assist_hint:-none}"
elif [[ -n "${nl_inference_skipped_reason}" ]]; then
  nl_line="- Natural-language hints: skipped (${nl_inference_skipped_reason})"
fi
content_line=""
if [[ "${content_hint_applied}" == "true" ]]; then
  content_line="- Content intent: skill=${content_skill_hint:-none}, action=${content_action_hint:-none}"
fi
fallback_block="$(printf '%s\n%s\n' "${main_fallback_note}" "${assist_fallback_note}" | sed '/^$/d')"
cat > handoff-comment.md <<EOF
GHA24 mainframe handoff (natural language)

- Mode: ${mode}
${provider_line}
${assist_provider_line}
${handoff_target_line}
${source_line}
${nl_line}
${content_line}
${vote_instruction_line}
${confirmation_line}
- Action: added labels \`fugue-task\` + \`tutti\`${extra}
${fallback_block}
${confirm_note}

Next: GitHub-hosted Tutti consensus starts now and continues development from the current issue state. You do not need to restate prior context; the current issue thread and labels are carried forward into the vote/execution flow.
EOF
gh issue comment "${ISSUE_NUMBER}" --repo "${GITHUB_REPOSITORY}" --body-file handoff-comment.md

# IMPORTANT: label events created by GitHub Actions' GITHUB_TOKEN do NOT trigger other workflows.
# We must dispatch the mainframe workflow explicitly.
dispatch_args=(
  --repo "${GITHUB_REPOSITORY}"
  -f issue_number="${ISSUE_NUMBER}"
)
dispatch_nonce="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-$(date -u +%Y%m%dT%H%M%SZ)"
dispatch_args+=(-f dispatch_nonce="${dispatch_nonce}")
dispatch_args+=(-f handoff_target="${handoff_target}")
dispatch_args+=(-f intake_source="${intake_source}")
dispatch_args+=(-f requested_execution_mode="${mode}")
dispatch_args+=(-f implement_request="${wants_implement}")
dispatch_args+=(-f implement_confirmed="${confirm_implement}")
dispatch_args+=(-f vote_command="${IS_VOTE_COMMAND}")
trust_subject="$(printf '%s' "${TRUST_SUBJECT:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${trust_subject}" ]]; then
  dispatch_args+=(-f trust_subject="${trust_subject}")
fi
if [[ -n "${vote_instruction_b64}" ]]; then
  dispatch_args+=(-f vote_instruction_b64="${vote_instruction_b64}")
fi
if [[ -n "${kernel_run_id_input}" ]]; then
  dispatch_args+=(-f kernel_run_id="${kernel_run_id_input}")
fi
if [[ "${IS_VOTE_COMMAND}" == "true" || "${allow_processing_rerun_input}" == "true" ]]; then
  dispatch_args+=(-f allow_processing_rerun="true")
fi
if [[ -n "${subscription_offline_policy_override}" ]]; then
  dispatch_args+=(-f subscription_offline_policy_override="${subscription_offline_policy_override}")
fi
if [[ "${resolved_execution_mode_override}" != "auto" ]]; then
  dispatch_args+=(-f execution_mode_override="${resolved_execution_mode_override}")
fi

bridge_handoff_script="scripts/harness/fugue-bridge-handoff.sh"
if [[ ! -x "${bridge_handoff_script}" && -x ".fugue-orchestrator/scripts/harness/fugue-bridge-handoff.sh" ]]; then
  bridge_handoff_script=".fugue-orchestrator/scripts/harness/fugue-bridge-handoff.sh"
fi

if [[ "${handoff_target}" == "fugue-bridge" ]]; then
  if [[ ! -x "${bridge_handoff_script}" ]]; then
    echo "fugue-bridge handoff requested, but adapter script is missing: ${bridge_handoff_script}" >&2
    exit 1
  fi
  bridge_args=(
    --repo "${GITHUB_REPOSITORY}"
    --issue-number "${ISSUE_NUMBER}"
    --dispatch-nonce "${dispatch_nonce}"
    --requested-execution-mode "${mode}"
    --implement-request "${wants_implement}"
    --implement-confirmed "${confirm_implement}"
    --vote-command "${IS_VOTE_COMMAND}"
    --intake-source "${intake_source}"
    --execution-mode-override "${resolved_execution_mode_override}"
  )
  if [[ -n "${trust_subject}" ]]; then
    bridge_args+=(--trust-subject "${trust_subject}")
  fi
  if [[ -n "${vote_instruction_b64}" ]]; then
    bridge_args+=(--vote-instruction-b64 "${vote_instruction_b64}")
  fi
  if [[ "${IS_VOTE_COMMAND}" == "true" || "${allow_processing_rerun_input}" == "true" ]]; then
    bridge_args+=(--allow-processing-rerun)
  fi
  if [[ -n "${subscription_offline_policy_override}" ]]; then
    bridge_args+=(--subscription-offline-policy-override "${subscription_offline_policy_override}")
  fi
  bash "${bridge_handoff_script}" "${bridge_args[@]}" >/dev/null
else
  gh workflow run fugue-tutti-caller.yml "${dispatch_args[@]}" >/dev/null
fi

echo "handoff=true" >> "${GITHUB_OUTPUT}"
echo "handoff_target=${handoff_target}" >> "${GITHUB_OUTPUT}"
echo "mode=${mode}" >> "${GITHUB_OUTPUT}"
