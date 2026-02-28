#!/usr/bin/env bash
set -euo pipefail

# Normalize model selections onto the supported "latest track" used by FUGUE.
# This protects runtime from stale or unsupported env overrides.

codex_main_model=""
codex_multi_agent_model=""
claude_model=""
glm_model=""
gemini_model=""
gemini_fallback_model=""
xai_model=""
format="env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex-main-model)
      codex_main_model="${2:-}"
      shift 2
      ;;
    --codex-multi-agent-model)
      codex_multi_agent_model="${2:-}"
      shift 2
      ;;
    --claude-model)
      claude_model="${2:-}"
      shift 2
      ;;
    --glm-model)
      glm_model="${2:-}"
      shift 2
      ;;
    --gemini-model)
      gemini_model="${2:-}"
      shift 2
      ;;
    --gemini-fallback-model)
      gemini_fallback_model="${2:-}"
      shift 2
      ;;
    --xai-model)
      xai_model="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-env}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: model-policy.sh [options]

Options:
  --codex-main-model VALUE
  --codex-multi-agent-model VALUE
  --claude-model VALUE
  --glm-model VALUE
  --gemini-model VALUE
  --gemini-fallback-model VALUE
  --xai-model VALUE
  --format VALUE                    env (default) | json
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

LATEST_CODEX_MAIN="gpt-5-codex"
LATEST_CODEX_MULTI_DEFAULT="gpt-5.3-codex-spark"
LATEST_CLAUDE_DEFAULT="claude-sonnet-4-6"
LATEST_GLM_DEFAULT="glm-4.5"
LATEST_GEMINI_PRIMARY="gemini-3.1-pro"
LATEST_GEMINI_FALLBACK="gemini-3-flash"
LATEST_XAI_DEFAULT="grok-4"

codex_main_raw="$(lower_trim "${codex_main_model}")"
codex_multi_raw="$(lower_trim "${codex_multi_agent_model}")"
claude_raw="$(lower_trim "${claude_model}")"
glm_raw="$(lower_trim "${glm_model}")"
gemini_raw="$(lower_trim "${gemini_model}")"
gemini_fallback_raw="$(lower_trim "${gemini_fallback_model}")"
xai_raw="$(lower_trim "${xai_model}")"

normalized_codex_main="${LATEST_CODEX_MAIN}"
normalized_codex_multi="${LATEST_CODEX_MULTI_DEFAULT}"
normalized_claude="${LATEST_CLAUDE_DEFAULT}"
normalized_glm="${LATEST_GLM_DEFAULT}"
normalized_gemini="${LATEST_GEMINI_PRIMARY}"
normalized_gemini_fallback="${LATEST_GEMINI_FALLBACK}"
normalized_xai="${LATEST_XAI_DEFAULT}"

adjusted="false"
adjustments=()

if [[ -n "${codex_main_raw}" && "${codex_main_raw}" != "${LATEST_CODEX_MAIN}" ]]; then
  adjusted="true"
  adjustments+=("codex_main:${codex_main_raw}->${LATEST_CODEX_MAIN}")
fi

if [[ -n "${codex_multi_raw}" ]]; then
  if [[ "${codex_multi_raw}" =~ ^gpt-5(\.[0-9]+)?-codex-spark$ ]]; then
    normalized_codex_multi="${codex_multi_raw}"
  else
    adjusted="true"
    adjustments+=("codex_multi:${codex_multi_raw}->${LATEST_CODEX_MULTI_DEFAULT}")
  fi
fi

# Current policy: Claude orchestration lanes stay on Sonnet 4.6.
if [[ -n "${claude_raw}" ]]; then
  if [[ "${claude_raw}" == "claude-sonnet-4-6" ]]; then
    normalized_claude="${claude_raw}"
  else
    adjusted="true"
    adjustments+=("claude:${claude_raw}->${LATEST_CLAUDE_DEFAULT}")
  fi
fi

if [[ -n "${glm_raw}" ]]; then
  if [[ "${glm_raw}" == "glm-4.5" || "${glm_raw}" =~ ^glm-5(\.[0-9]+)?$ ]]; then
    normalized_glm="${glm_raw}"
  else
    adjusted="true"
    adjustments+=("glm:${glm_raw}->${LATEST_GLM_DEFAULT}")
  fi
fi

if [[ -n "${gemini_raw}" ]]; then
  if [[ "${gemini_raw}" == "gemini-3.1-pro" || "${gemini_raw}" == "gemini-3-flash" ]]; then
    normalized_gemini="${gemini_raw}"
  else
    adjusted="true"
    adjustments+=("gemini:${gemini_raw}->${LATEST_GEMINI_PRIMARY}")
  fi
fi

if [[ -n "${gemini_fallback_raw}" ]]; then
  if [[ "${gemini_fallback_raw}" == "gemini-3.1-pro" || "${gemini_fallback_raw}" == "gemini-3-flash" ]]; then
    normalized_gemini_fallback="${gemini_fallback_raw}"
  else
    adjusted="true"
    adjustments+=("gemini_fallback:${gemini_fallback_raw}->${LATEST_GEMINI_FALLBACK}")
  fi
fi

if [[ -n "${xai_raw}" ]]; then
  if [[ "${xai_raw}" =~ ^grok-4([.-].+)?$ ]]; then
    normalized_xai="${xai_raw}"
  else
    adjusted="true"
    adjustments+=("xai:${xai_raw}->${LATEST_XAI_DEFAULT}")
  fi
fi

adjustments_joined=""
if [[ ${#adjustments[@]} -gt 0 ]]; then
  adjustments_joined="$(IFS=';'; echo "${adjustments[*]}")"
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg codex_main_model "${normalized_codex_main}" \
    --arg codex_multi_agent_model "${normalized_codex_multi}" \
    --arg claude_model "${normalized_claude}" \
    --arg glm_model "${normalized_glm}" \
    --arg gemini_model "${normalized_gemini}" \
    --arg gemini_fallback_model "${normalized_gemini_fallback}" \
    --arg xai_model "${normalized_xai}" \
    --arg adjusted "${adjusted}" \
    --arg adjustments "${adjustments_joined}" \
    '{
      codex_main_model:$codex_main_model,
      codex_multi_agent_model:$codex_multi_agent_model,
      claude_model:$claude_model,
      glm_model:$glm_model,
      gemini_model:$gemini_model,
      gemini_fallback_model:$gemini_fallback_model,
      xai_model:$xai_model,
      adjusted:($adjusted == "true"),
      adjustments:$adjustments
    }'
  exit 0
fi

printf 'codex_main_model=%q\n' "${normalized_codex_main}"
printf 'codex_multi_agent_model=%q\n' "${normalized_codex_multi}"
printf 'claude_model=%q\n' "${normalized_claude}"
printf 'glm_model=%q\n' "${normalized_glm}"
printf 'gemini_model=%q\n' "${normalized_gemini}"
printf 'gemini_fallback_model=%q\n' "${normalized_gemini_fallback}"
printf 'xai_model=%q\n' "${normalized_xai}"
printf 'model_policy_adjusted=%q\n' "${adjusted}"
printf 'model_policy_adjustments=%q\n' "${adjustments_joined}"
