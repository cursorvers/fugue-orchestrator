#!/usr/bin/env bash
set -euo pipefail

# Shared agent matrix builder for GHA Tutti and local orchestration.
# This script centralizes lane topology so workflow/local drift is detectable.

engine="subscription"
main_provider="codex"
assist_provider="claude"
multi_agent_mode="standard"
glm_subagent_mode="paired"
wants_gemini="false"
wants_xai="false"
allow_glm_in_subscription="false"
dual_main_signal="false"
codex_main_model="gpt-5-codex"
codex_multi_agent_model="gpt-5.3-codex-spark"
claude_opus_model="claude-sonnet-4-6"
claude_sonnet4_model="claude-sonnet-4-6"
claude_sonnet6_model="claude-sonnet-4-6"
glm_model="glm-5.0"
gemini_model="gemini-3.1-pro"
xai_model="grok-4"
format="json"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model_policy_script="${script_dir}/model-policy.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      engine="${2:-subscription}"
      shift 2
      ;;
    --main-provider)
      main_provider="${2:-codex}"
      shift 2
      ;;
    --assist-provider)
      assist_provider="${2:-claude}"
      shift 2
      ;;
    --multi-agent-mode)
      multi_agent_mode="${2:-standard}"
      shift 2
      ;;
    --glm-subagent-mode)
      glm_subagent_mode="${2:-paired}"
      shift 2
      ;;
    --wants-gemini)
      wants_gemini="${2:-false}"
      shift 2
      ;;
    --wants-xai)
      wants_xai="${2:-false}"
      shift 2
      ;;
    --allow-glm-in-subscription)
      allow_glm_in_subscription="${2:-false}"
      shift 2
      ;;
    --dual-main-signal)
      dual_main_signal="${2:-false}"
      shift 2
      ;;
    --codex-main-model)
      codex_main_model="${2:-gpt-5-codex}"
      shift 2
      ;;
    --codex-multi-agent-model)
      codex_multi_agent_model="${2:-gpt-5.3-codex-spark}"
      shift 2
      ;;
    --claude-opus-model)
      claude_opus_model="${2:-claude-sonnet-4-6}"
      shift 2
      ;;
    --claude-sonnet4-model)
      claude_sonnet4_model="${2:-claude-sonnet-4-6}"
      shift 2
      ;;
    --claude-sonnet6-model)
      claude_sonnet6_model="${2:-claude-sonnet-4-6}"
      shift 2
      ;;
    --glm-model)
      glm_model="${2:-glm-5.0}"
      shift 2
      ;;
    --gemini-model)
      gemini_model="${2:-gemini-3.1-pro}"
      shift 2
      ;;
    --xai-model)
      xai_model="${2:-grok-4}"
      shift 2
      ;;
    --format)
      format="${2:-json}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: build-agent-matrix.sh [options]

Options:
  --engine VALUE                    subscription|harness|api
  --main-provider VALUE             codex|claude
  --assist-provider VALUE           claude|codex|none
  --multi-agent-mode VALUE          standard|enhanced|max
  --glm-subagent-mode VALUE         off|paired|symphony
  --wants-gemini VALUE              true|false
  --wants-xai VALUE                 true|false
  --allow-glm-in-subscription VALUE true|false (local hybrid mode switch)
  --dual-main-signal VALUE          true|false (include both codex/claude main signal lanes)
  --codex-main-model VALUE          default: gpt-5-codex
  --codex-multi-agent-model VALUE   default: gpt-5.3-codex-spark
  --claude-opus-model VALUE         default: claude-sonnet-4-6
  --claude-sonnet4-model VALUE      default: claude-sonnet-4-6
  --claude-sonnet6-model VALUE      default: claude-sonnet-4-6
  --glm-model VALUE                 default: glm-5.0
  --gemini-model VALUE              default: gemini-3.1-pro
  --xai-model VALUE                 default: grok-4
  --format VALUE                    json (default) | env

Output (json):
{
  "matrix": {"include":[...]},
  "lanes": 15,
  "main_signal_lane": "codex-main-orchestrator",
  "use_glm_baseline": true
}
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

normalize_bool() {
  local v
  v="$(lower_trim "$1")"
  if [[ "${v}" == "true" || "${v}" == "1" || "${v}" == "yes" || "${v}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

engine="$(lower_trim "${engine}")"
if [[ "${engine}" != "subscription" && "${engine}" != "harness" && "${engine}" != "api" ]]; then
  engine="subscription"
fi
main_provider="$(lower_trim "${main_provider}")"
if [[ "${main_provider}" != "codex" && "${main_provider}" != "claude" ]]; then
  main_provider="codex"
fi
assist_provider="$(lower_trim "${assist_provider}")"
if [[ "${assist_provider}" != "claude" && "${assist_provider}" != "codex" && "${assist_provider}" != "none" ]]; then
  assist_provider="none"
fi
multi_agent_mode="$(lower_trim "${multi_agent_mode}")"
if [[ "${multi_agent_mode}" != "standard" && "${multi_agent_mode}" != "enhanced" && "${multi_agent_mode}" != "max" ]]; then
  multi_agent_mode="standard"
fi
glm_subagent_mode="$(lower_trim "${glm_subagent_mode}")"
if [[ "${glm_subagent_mode}" != "off" && "${glm_subagent_mode}" != "paired" && "${glm_subagent_mode}" != "symphony" ]]; then
  glm_subagent_mode="paired"
fi
wants_gemini="$(normalize_bool "${wants_gemini}")"
wants_xai="$(normalize_bool "${wants_xai}")"
allow_glm_in_subscription="$(normalize_bool "${allow_glm_in_subscription}")"
dual_main_signal="$(normalize_bool "${dual_main_signal}")"
# shellcheck source=safe-eval-policy.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/safe-eval-policy.sh"
if [[ -x "${model_policy_script}" ]]; then
  safe_eval_policy "${model_policy_script}" \
    --codex-main-model "${codex_main_model}" \
    --codex-multi-agent-model "${codex_multi_agent_model}" \
    --claude-model "${claude_opus_model}" \
    --glm-model "${glm_model}" \
    --gemini-model "${gemini_model}" \
    --xai-model "${xai_model}" \
    --format env
  claude_opus_model="${claude_model}"
  claude_sonnet4_model="${claude_model}"
  claude_sonnet6_model="${claude_model}"
else
  if [[ -z "${codex_main_model}" ]]; then
    codex_main_model="gpt-5-codex"
  fi
  if [[ -z "${codex_multi_agent_model}" ]]; then
    codex_multi_agent_model="gpt-5.3-codex-spark"
  fi
  if [[ -z "${claude_opus_model}" ]]; then
    claude_opus_model="claude-sonnet-4-6"
  fi
  if [[ -z "${claude_sonnet4_model}" ]]; then
    claude_sonnet4_model="claude-sonnet-4-6"
  fi
  if [[ -z "${claude_sonnet6_model}" ]]; then
    claude_sonnet6_model="claude-sonnet-4-6"
  fi
  if [[ -z "${glm_model}" ]]; then
    glm_model="glm-5.0"
  fi
  if [[ -z "${gemini_model}" ]]; then
    gemini_model="gemini-3.1-pro"
  fi
  if [[ -z "${xai_model}" ]]; then
    xai_model="grok-4"
  fi
fi

use_glm_baseline="false"
if [[ "${engine}" != "subscription" || "${allow_glm_in_subscription}" == "true" ]]; then
  use_glm_baseline="true"
fi

if [[ "${engine}" == "subscription" && "${allow_glm_in_subscription}" != "true" ]]; then
  wants_gemini="false"
  wants_xai="false"
fi

main_signal_lane="codex-main-orchestrator"
secondary_main_signal_lane="claude-main-orchestrator"
if [[ "${main_provider}" == "claude" ]]; then
  main_signal_lane="claude-main-orchestrator"
  secondary_main_signal_lane="codex-main-orchestrator"
fi

matrix="$(jq -cn \
  --arg engine "${engine}" \
  --arg main_provider "${main_provider}" \
  --arg assist_provider "${assist_provider}" \
  --arg multi_agent_mode "${multi_agent_mode}" \
  --arg glm_subagent_mode "${glm_subagent_mode}" \
  --arg codex_main_model "${codex_main_model}" \
  --arg codex_multi_agent_model "${codex_multi_agent_model}" \
  --arg claude_opus_model "${claude_opus_model}" \
  --arg claude_sonnet4_model "${claude_sonnet4_model}" \
  --arg claude_sonnet6_model "${claude_sonnet6_model}" \
  --arg glm_model "${glm_model}" \
  --arg gemini_model "${gemini_model}" \
  --arg xai_model "${xai_model}" \
  --argjson wants_gemini "$( [[ "${wants_gemini}" == "true" ]] && echo true || echo false )" \
  --argjson wants_xai "$( [[ "${wants_xai}" == "true" ]] && echo true || echo false )" \
  --argjson use_glm_baseline "$( [[ "${use_glm_baseline}" == "true" ]] && echo true || echo false )" \
  --argjson dual_main_signal "$( [[ "${dual_main_signal}" == "true" ]] && echo true || echo false )" \
  '
  # --- Provider API URL resolvers ---
  def codex_api: if $engine == "subscription" then "subscription-cli" else "https://api.openai.com/v1/chat/completions" end;
  def claude_api: if $engine == "subscription" then "subscription-cli" else "https://api.anthropic.com/v1/messages" end;
  def glm_api: "https://api.z.ai/api/coding/paas/v4/chat/completions";
  def gemini_api: "https://generativelanguage.googleapis.com/v1beta/models";
  def xai_api: "https://api.x.ai/v1/chat/completions";

  # --- Lane constructors ---
  def L(n;p;u;m;r): {name:n, provider:p, api_url:u, model:m, agent_role:r};
  def Ld(n;p;u;m;r;d): L(n;p;u;m;r) + {agent_directive:d};
  def codex(n;r): L(n; "codex"; codex_api; $codex_multi_agent_model; r);
  def codex_sub(n;r): L(n; "codex"; "subscription-cli"; $codex_multi_agent_model; r);
  def glm(n;r): L(n; "glm"; glm_api; $glm_model; r);
  def glmd(n;r;d): Ld(n; "glm"; glm_api; $glm_model; r; d);
  def enhanced_or_max: ($multi_agent_mode == "enhanced" or $multi_agent_mode == "max");

  # --- Base lanes ---
  def base:
    if $use_glm_baseline then
      [ codex("codex-security-analyst";"security-analyst"),
        codex("codex-code-reviewer";"code-reviewer"),
        codex("codex-general-reviewer";"general-reviewer"),
        glm("glm-code-reviewer";"code-reviewer"),
        glm("glm-general-reviewer";"general-reviewer"),
        glm("glm-math-reasoning";"math-reasoning") ]
    else
      [ codex_sub("codex-security-analyst";"security-analyst"),
        codex_sub("codex-code-reviewer";"code-reviewer"),
        codex_sub("codex-general-reviewer";"general-reviewer"),
        codex_sub("codex-math-reasoning";"math-reasoning"),
        codex_sub("codex-refactor-advisor";"refactor-advisor"),
        codex_sub("codex-general-critic";"general-critic") ]
    end;

  {include: base}
  # GLM orchestration subagent
  | if ($use_glm_baseline and $glm_subagent_mode != "off") then
      .include += [glmd("glm-orchestration-subagent";"orchestration-assistant";
        "Work as Codex main orchestrator subagent: surface hidden assumptions, unresolved dependencies, and handoff risks.")]
    else . end
  # Main orchestrator lane
  | if $main_provider == "claude" then
      .include += [L("claude-main-orchestrator";"claude";claude_api;$claude_opus_model;"main-orchestrator")]
    else
      .include += [L("codex-main-orchestrator";"codex";codex_api;$codex_main_model;"main-orchestrator")]
    end
  # Dual main signal (secondary)
  | if $dual_main_signal then
      if $main_provider == "claude" then
        .include += [L("codex-main-orchestrator";"codex";codex_api;$codex_main_model;"main-orchestrator")]
      else
        .include += [L("claude-main-orchestrator";"claude";claude_api;$claude_opus_model;"main-orchestrator")]
      end
    else . end
  # Assist lanes
  | if $assist_provider == "claude" then
      .include += [L("claude-opus-assist";"claude";claude_api;$claude_opus_model;"orchestration-assistant")]
    else . end
  | if $assist_provider == "claude" and $engine != "subscription" then
      .include += [
        L("claude-sonnet4-assist";"claude";claude_api;$claude_sonnet4_model;"orchestration-assistant"),
        L("claude-sonnet6-assist";"claude";claude_api;$claude_sonnet6_model;"orchestration-assistant")]
    else . end
  | if $assist_provider == "codex" then
      .include += [codex("codex-orchestration-assist";"orchestration-assistant")]
    else . end
  # Optional provider lanes
  | if $wants_gemini then
      .include += [L("gemini-visual-reviewer";"gemini";gemini_api;$gemini_model;"ui-reviewer")]
    else . end
  | if $wants_xai then
      .include += [L("xai-realtime-info";"xai";xai_api;$xai_model;"realtime-info")]
    else . end
  # Enhanced/Max mode lanes
  | if enhanced_or_max then
      .include += [codex("codex-architect";"architect"), codex("codex-plan-reviewer";"plan-reviewer")]
    else . end
  | if enhanced_or_max and ($use_glm_baseline | not) then
      .include += [codex_sub("codex-refactor-advisor-enhanced";"refactor-advisor"), codex_sub("codex-general-critic-enhanced";"general-critic")]
    else . end
  | if enhanced_or_max and $use_glm_baseline then
      .include += [glm("glm-refactor-advisor";"refactor-advisor"), glm("glm-general-critic";"general-critic")]
    else . end
  | if enhanced_or_max and $use_glm_baseline and $glm_subagent_mode != "off" then
      .include += [
        glmd("glm-architect-subagent";"architect";
          "Act as GLM subagent to stress-test the system architecture and expose hidden coupling before implementation."),
        glmd("glm-plan-reviewer-subagent";"plan-reviewer";
          "Act as GLM subagent to challenge plan sequencing, rollback feasibility, and dependency ordering.")]
    else . end
  # Max-only lanes
  | if $multi_agent_mode == "max" then
      .include += [codex("codex-reliability-engineer";"reliability-engineer")]
    else . end
  | if $multi_agent_mode == "max" and ($use_glm_baseline | not) then
      .include += [codex_sub("codex-invariants-checker";"invariants-checker")]
    else . end
  | if $multi_agent_mode == "max" and $use_glm_baseline then
      .include += [glm("glm-invariants-checker";"invariants-checker")]
    else . end
  | if $multi_agent_mode == "max" and $use_glm_baseline and $glm_subagent_mode == "symphony" then
      .include += [glmd("glm-reliability-subagent";"reliability-engineer";
        "Act as GLM subagent for worst-case operational scenarios, retries, and failure isolation.")]
    else . end
  ' )"

lanes="$(echo "${matrix}" | jq -r '.include | length')"

# Validate matrix before output.
validate_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-agent-matrix.sh"
if [[ -x "${validate_script}" ]]; then
  "${validate_script}" \
    --matrix "${matrix}" \
    --lanes "${lanes}" \
    --main-signal-lane "${main_signal_lane}" >&2 || exit 1
fi

if [[ "${format}" == "env" ]]; then
  printf 'matrix=%q\n' "${matrix}"
  printf 'lanes=%q\n' "${lanes}"
  printf 'main_signal_lane=%q\n' "${main_signal_lane}"
  printf 'main_signal_lanes=%q\n' "$(jq -cn --arg primary "${main_signal_lane}" --arg secondary "${secondary_main_signal_lane}" --argjson dual "$( [[ "${dual_main_signal}" == "true" ]] && echo true || echo false )" '[$primary] + (if $dual and ($secondary|length)>0 then [$secondary] else [] end)')"
  printf 'use_glm_baseline=%q\n' "${use_glm_baseline}"
  exit 0
fi

jq -cn \
  --argjson matrix "${matrix}" \
  --argjson lanes "${lanes}" \
  --arg main_signal_lane "${main_signal_lane}" \
  --arg secondary_main_signal_lane "${secondary_main_signal_lane}" \
  --argjson dual_main_signal "$( [[ "${dual_main_signal}" == "true" ]] && echo true || echo false )" \
  --argjson use_glm_baseline "$( [[ "${use_glm_baseline}" == "true" ]] && echo true || echo false )" \
  '{
    matrix:$matrix,
    lanes:$lanes,
    main_signal_lane:$main_signal_lane,
    main_signal_lanes:([$main_signal_lane] + (if $dual_main_signal and ($secondary_main_signal_lane|length)>0 then [$secondary_main_signal_lane] else [] end)),
    use_glm_baseline:$use_glm_baseline
  }'
