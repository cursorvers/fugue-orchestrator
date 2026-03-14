#!/usr/bin/env bash

fugue_provider_success_count() {
  local results_file="$1"
  local provider="$2"
  local exclude_glm_subagents="${3:-false}"

  jq -r \
    --arg provider "${provider}" \
    --argjson exclude_glm_subagents "$( [[ "${exclude_glm_subagents}" == "true" ]] && echo "true" || echo "false" )" \
    '[
      .[] | select(
        .skipped != true
        and ((.fallback_used // false) != true)
        and ((.provider // "" | ascii_downcase) == $provider)
        and (
          ((.http_code // "" | tostring) == "200")
          or
          ((.http_code // "" | tostring | startswith("cli:0")))
        )
        and (
          if ($provider == "glm") and $exclude_glm_subagents
          then ((.name // "") | test("^glm-.*-subagent$") | not)
          else true
          end
        )
      )
    ] | length' "${results_file}"
}

fugue_shadow_continuity_families() {
  local results_file="$1"

  jq -r '
    [
      .[] | select(
        .skipped != true
        and (
          (((.fallback_used // false) == true) and ((.fallback_provider // "") | length > 0))
          or
          ((.provider // "" | ascii_downcase) == "copilot")
          or
          ((.provider // "" | ascii_downcase) == "gemini")
          or
          ((.provider // "" | ascii_downcase) == "xai")
        )
        and (
          ((.http_code // "" | tostring) == "200")
          or
          ((.http_code // "" | tostring | startswith("cli:0")))
        )
      )
      | (
          if ((.fallback_used // false) == true) and ((.fallback_provider // "") | length > 0)
          then (.fallback_provider // "" | ascii_downcase | sub("-cli$"; ""))
          else (.provider // "" | ascii_downcase)
          end
        )
      | select(. != "codex" and . != "")
    ] | unique | join(",")
  ' "${results_file}"
}

fugue_shadow_continuity_success_count() {
  local results_file="$1"

  jq -r '
    [
      .[] | select(
        .skipped != true
        and (
          (((.fallback_used // false) == true) and ((.fallback_provider // "") | length > 0))
          or
          ((.provider // "" | ascii_downcase) == "copilot")
          or
          ((.provider // "" | ascii_downcase) == "gemini")
          or
          ((.provider // "" | ascii_downcase) == "xai")
        )
        and (
          ((.http_code // "" | tostring) == "200")
          or
          ((.http_code // "" | tostring | startswith("cli:0")))
        )
      )
      | (
          if ((.fallback_used // false) == true) and ((.fallback_provider // "") | length > 0)
          then (.fallback_provider // "" | ascii_downcase | sub("-cli$"; ""))
          else (.provider // "" | ascii_downcase)
          end
        )
      | select(. != "codex" and . != "")
    ] | unique | length
  ' "${results_file}"
}

fugue_effective_non_codex_families() {
  local results_file="$1"

  jq -r '
    [
      .[] | select(
        .skipped != true
        and (
          ((.http_code // "" | tostring) == "200")
          or
          ((.http_code // "" | tostring | startswith("cli:0")))
        )
      )
      | (
          if ((.fallback_used // false) == true) and ((.fallback_provider // "") | length > 0)
          then (.fallback_provider // "" | ascii_downcase | sub("-cli$"; ""))
          else (.provider // "" | ascii_downcase)
          end
        )
      | select(. != "" and . != "codex")
    ] | unique | join(",")
  ' "${results_file}"
}

fugue_effective_non_codex_success_count() {
  local results_file="$1"

  jq -r '
    [
      .[] | select(
        .skipped != true
        and (
          ((.http_code // "" | tostring) == "200")
          or
          ((.http_code // "" | tostring | startswith("cli:0")))
        )
      )
      | (
          if ((.fallback_used // false) == true) and ((.fallback_provider // "") | length > 0)
          then (.fallback_provider // "" | ascii_downcase | sub("-cli$"; ""))
          else (.provider // "" | ascii_downcase)
          end
        )
      | select(. != "" and . != "codex")
    ] | unique | length
  ' "${results_file}"
}

fugue_missing_lane_shadow_families() {
  local results_file="$1"
  local missing_lane="$2"

  jq -r \
    --arg missing_lane "${missing_lane}" \
    '
      [
        .[] | select(
          .skipped != true
          and ((.fallback_used // false) == true)
          and ((.missing_lane // "" | ascii_downcase) == ($missing_lane | ascii_downcase))
          and ((.fallback_provider // "") | length > 0)
          and (
            ((.http_code // "" | tostring) == "200")
            or
            ((.http_code // "" | tostring | startswith("cli:0")))
          )
        )
        | (.fallback_provider // "" | ascii_downcase | sub("-cli$"; ""))
        | select(. != "")
      ] | unique | join(",")
    ' "${results_file}"
}

fugue_missing_lane_shadow_success_count() {
  local results_file="$1"
  local missing_lane="$2"

  jq -r \
    --arg missing_lane "${missing_lane}" \
    '
      [
        .[] | select(
          .skipped != true
          and ((.fallback_used // false) == true)
          and ((.missing_lane // "" | ascii_downcase) == ($missing_lane | ascii_downcase))
          and ((.fallback_provider // "") | length > 0)
          and (
            ((.http_code // "" | tostring) == "200")
            or
            ((.http_code // "" | tostring | startswith("cli:0")))
          )
        )
      ] | length
    ' "${results_file}"
}

fugue_calculate_baseline_trio_policy() {
  local results_file="$1"
  local require_baseline_trio="$2"
  local baseline_missing=()

  FUGUE_BASELINE_CODEX_SUCCESS="$(fugue_provider_success_count "${results_file}" "codex")"
  FUGUE_BASELINE_CLAUDE_SUCCESS="$(fugue_provider_success_count "${results_file}" "claude")"
  FUGUE_BASELINE_GLM_SUCCESS="$(fugue_provider_success_count "${results_file}" "glm" "true")"
  FUGUE_SHADOW_CONTINUITY_FAMILIES="$(fugue_shadow_continuity_families "${results_file}")"
  FUGUE_SHADOW_CONTINUITY_SUCCESS_COUNT="$(fugue_shadow_continuity_success_count "${results_file}")"
  FUGUE_EFFECTIVE_NON_CODEX_FAMILIES="$(fugue_effective_non_codex_families "${results_file}")"
  FUGUE_EFFECTIVE_NON_CODEX_SUCCESS_COUNT="$(fugue_effective_non_codex_success_count "${results_file}")"
  FUGUE_BASELINE_TRIO_GATE="not-required"
  FUGUE_BASELINE_TRIO_REASON="policy-disabled"
  FUGUE_BASELINE_HIGH_RISK_BUMP="false"
  FUGUE_BASELINE_FORCE_WEIGHTED_VOTE_FALSE="false"

  if [[ "${require_baseline_trio}" != "true" ]]; then
    return 0
  fi

  FUGUE_BASELINE_TRIO_GATE="pass"
  if [[ "${FUGUE_BASELINE_CODEX_SUCCESS}" -eq 0 ]]; then
    baseline_missing+=("codex")
  fi
  if [[ "${FUGUE_BASELINE_CLAUDE_SUCCESS}" -eq 0 ]]; then
    baseline_missing+=("claude")
  fi
  if [[ "${FUGUE_BASELINE_GLM_SUCCESS}" -eq 0 ]]; then
    baseline_missing+=("glm")
  fi

  if (( ${#baseline_missing[@]} == 0 )); then
    FUGUE_BASELINE_TRIO_REASON="codex+claude+glm-ok"
    return 0
  fi

  if [[ "${FUGUE_BASELINE_CODEX_SUCCESS}" -gt 0 && "${FUGUE_EFFECTIVE_NON_CODEX_SUCCESS_COUNT}" -ge 2 ]]; then
    FUGUE_BASELINE_TRIO_GATE="recovery-pass"
    FUGUE_BASELINE_TRIO_REASON="missing-$(IFS=,; echo "${baseline_missing[*]}");fallback-quorum=${FUGUE_EFFECTIVE_NON_CODEX_FAMILIES}"
    return 0
  fi

  FUGUE_BASELINE_TRIO_GATE="fail"
  FUGUE_BASELINE_TRIO_REASON="missing-$(IFS=,; echo "${baseline_missing[*]}")"
  if [[ "${FUGUE_SHADOW_CONTINUITY_SUCCESS_COUNT}" -gt 0 ]]; then
    FUGUE_BASELINE_TRIO_REASON="${FUGUE_BASELINE_TRIO_REASON};shadow-continuity=${FUGUE_SHADOW_CONTINUITY_FAMILIES}"
  fi
  FUGUE_BASELINE_HIGH_RISK_BUMP="true"
  FUGUE_BASELINE_FORCE_WEIGHTED_VOTE_FALSE="true"
}
