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
if [[ -x "${model_policy_script}" ]]; then
  eval "$("${model_policy_script}" \
    --codex-main-model "${codex_main_model}" \
    --codex-multi-agent-model "${codex_multi_agent_model}" \
    --claude-model "${claude_opus_model}" \
    --glm-model "${glm_model}" \
    --gemini-model "${gemini_model}" \
    --xai-model "${xai_model}" \
    --format env)"
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
  def codex_api($engine):
    if $engine == "subscription" then "subscription-cli" else "https://api.openai.com/v1/chat/completions" end;
  def claude_api($engine):
    if $engine == "subscription" then "subscription-cli" else "https://api.anthropic.com/v1/messages" end;

  def base($use_glm_baseline; $codex_multi_agent_model):
    if $use_glm_baseline then
      [
        {name:"codex-security-analyst",provider:"codex",api_url:codex_api($engine),model:$codex_multi_agent_model,agent_role:"security-analyst"},
        {name:"codex-code-reviewer",provider:"codex",api_url:codex_api($engine),model:$codex_multi_agent_model,agent_role:"code-reviewer"},
        {name:"codex-general-reviewer",provider:"codex",api_url:codex_api($engine),model:$codex_multi_agent_model,agent_role:"general-reviewer"},
        {name:"glm-code-reviewer",provider:"glm",api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",model:$glm_model,agent_role:"code-reviewer"},
        {name:"glm-general-reviewer",provider:"glm",api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",model:$glm_model,agent_role:"general-reviewer"},
        {name:"glm-math-reasoning",provider:"glm",api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",model:$glm_model,agent_role:"math-reasoning"}
      ]
    else
      [
        {name:"codex-security-analyst",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"security-analyst"},
        {name:"codex-code-reviewer",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"code-reviewer"},
        {name:"codex-general-reviewer",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"general-reviewer"},
        {name:"codex-math-reasoning",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"math-reasoning"},
        {name:"codex-refactor-advisor",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"refactor-advisor"},
        {name:"codex-general-critic",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"general-critic"}
      ]
    end;

  {include: base($use_glm_baseline; $codex_multi_agent_model)}
  | if ($use_glm_baseline and $glm_subagent_mode != "off") then
      .include += [{
        name:"glm-orchestration-subagent",
        provider:"glm",
        api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",
        model:$glm_model,
        agent_role:"orchestration-assistant",
        agent_directive:"Work as Codex main orchestrator subagent: surface hidden assumptions, unresolved dependencies, and handoff risks."
      }]
    else . end
  | if $main_provider == "claude" then
      .include += [{
        name:"claude-main-orchestrator",
        provider:"claude",
        api_url:claude_api($engine),
        model:$claude_opus_model,
        agent_role:"main-orchestrator"
      }]
    else
      .include += [{
        name:"codex-main-orchestrator",
        provider:"codex",
        api_url:codex_api($engine),
        model:$codex_main_model,
        agent_role:"main-orchestrator"
      }]
    end
  | if $dual_main_signal then
      if $main_provider == "claude" then
        .include += [{
          name:"codex-main-orchestrator",
          provider:"codex",
          api_url:codex_api($engine),
          model:$codex_main_model,
          agent_role:"main-orchestrator"
        }]
      else
        .include += [{
          name:"claude-main-orchestrator",
          provider:"claude",
          api_url:claude_api($engine),
          model:$claude_opus_model,
          agent_role:"main-orchestrator"
        }]
      end
    else . end
  | if $assist_provider == "claude" then
      .include += [{
        name:"claude-opus-assist",
        provider:"claude",
        api_url:claude_api($engine),
        model:$claude_opus_model,
        agent_role:"orchestration-assistant"
      }]
    else . end
  | if $assist_provider == "claude" and $engine != "subscription" then
      .include += [
        {name:"claude-sonnet4-assist",provider:"claude",api_url:claude_api($engine),model:$claude_sonnet4_model,agent_role:"orchestration-assistant"},
        {name:"claude-sonnet6-assist",provider:"claude",api_url:claude_api($engine),model:$claude_sonnet6_model,agent_role:"orchestration-assistant"}
      ]
    else . end
  | if $assist_provider == "codex" then
      .include += [{
        name:"codex-orchestration-assist",
        provider:"codex",
        api_url:codex_api($engine),
        model:$codex_multi_agent_model,
        agent_role:"orchestration-assistant"
      }]
    else . end
  | if $wants_gemini then
      .include += [{
        name:"gemini-visual-reviewer",
        provider:"gemini",
        api_url:"https://generativelanguage.googleapis.com/v1beta/models",
        model:$gemini_model,
        agent_role:"ui-reviewer"
      }]
    else . end
  | if $wants_xai then
      .include += [{
        name:"xai-realtime-info",
        provider:"xai",
        api_url:"https://api.x.ai/v1/chat/completions",
        model:$xai_model,
        agent_role:"realtime-info"
      }]
    else . end
  | if ($multi_agent_mode == "enhanced" or $multi_agent_mode == "max") then
      .include += [
        {name:"codex-architect",provider:"codex",api_url:codex_api($engine),model:$codex_multi_agent_model,agent_role:"architect"},
        {name:"codex-plan-reviewer",provider:"codex",api_url:codex_api($engine),model:$codex_multi_agent_model,agent_role:"plan-reviewer"}
      ]
    else . end
  | if ($multi_agent_mode == "enhanced" or $multi_agent_mode == "max") and ($use_glm_baseline | not) then
      .include += [
        {name:"codex-refactor-advisor-enhanced",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"refactor-advisor"},
        {name:"codex-general-critic-enhanced",provider:"codex",api_url:"subscription-cli",model:$codex_multi_agent_model,agent_role:"general-critic"}
      ]
    else . end
  | if ($multi_agent_mode == "enhanced" or $multi_agent_mode == "max") and $use_glm_baseline then
      .include += [
        {name:"glm-refactor-advisor",provider:"glm",api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",model:$glm_model,agent_role:"refactor-advisor"},
        {name:"glm-general-critic",provider:"glm",api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",model:$glm_model,agent_role:"general-critic"}
      ]
    else . end
  | if ($multi_agent_mode == "enhanced" or $multi_agent_mode == "max") and $use_glm_baseline and $glm_subagent_mode != "off" then
      .include += [
        {
          name:"glm-architect-subagent",
          provider:"glm",
          api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",
          model:$glm_model,
          agent_role:"architect",
          agent_directive:"Act as GLM subagent to stress-test the system architecture and expose hidden coupling before implementation."
        },
        {
          name:"glm-plan-reviewer-subagent",
          provider:"glm",
          api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",
          model:$glm_model,
          agent_role:"plan-reviewer",
          agent_directive:"Act as GLM subagent to challenge plan sequencing, rollback feasibility, and dependency ordering."
        }
      ]
    else . end
  | if $multi_agent_mode == "max" then
      .include += [{
        name:"codex-reliability-engineer",
        provider:"codex",
        api_url:codex_api($engine),
        model:$codex_multi_agent_model,
        agent_role:"reliability-engineer"
      }]
    else . end
  | if $multi_agent_mode == "max" and ($use_glm_baseline | not) then
      .include += [{
        name:"codex-invariants-checker",
        provider:"codex",
        api_url:"subscription-cli",
        model:$codex_multi_agent_model,
        agent_role:"invariants-checker"
      }]
    else . end
  | if $multi_agent_mode == "max" and $use_glm_baseline then
      .include += [{
        name:"glm-invariants-checker",
        provider:"glm",
        api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",
        model:$glm_model,
        agent_role:"invariants-checker"
      }]
    else . end
  | if $multi_agent_mode == "max" and $use_glm_baseline and $glm_subagent_mode == "symphony" then
      .include += [{
        name:"glm-reliability-subagent",
        provider:"glm",
        api_url:"https://api.z.ai/api/coding/paas/v4/chat/completions",
        model:$glm_model,
        agent_role:"reliability-engineer",
        agent_directive:"Act as GLM subagent for worst-case operational scenarios, retries, and failure isolation."
      }]
    else . end
  ' )"

lanes="$(echo "${matrix}" | jq -r '.include | length')"

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
