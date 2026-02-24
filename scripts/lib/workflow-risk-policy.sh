#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: workflow-risk-policy.sh [options]
  --title <string>
  --body <string>
  --labels <comma-separated labels>
  --has-implement <true|false>
  --orchestration-profile <codex-full|claude-light>

Environment overrides:
  FUGUE_CONTEXT_BUDGET_MIN_INITIAL  Minimum initial source budget floor (default: 6)
  FUGUE_CONTEXT_BUDGET_MIN_MAX      Minimum max source budget floor (default: 12)
  FUGUE_CONTEXT_BUDGET_MIN_SPAN     Minimum expansion span max-initial (default: 6, hard floor 4)
USAGE
}

title=""
body=""
labels_csv=""
has_implement="false"
orchestration_profile="codex-full"

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
    --labels)
      labels_csv="${2:-}"
      shift 2
      ;;
    --has-implement)
      has_implement="${2:-false}"
      shift 2
      ;;
    --orchestration-profile)
      orchestration_profile="${2:-codex-full}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

has_implement="$(echo "${has_implement}" | tr '[:upper:]' '[:lower:]')"
if [[ "${has_implement}" != "true" ]]; then
  has_implement="false"
fi

parse_non_negative_int() {
  local raw="${1:-}"
  local fallback="${2:-0}"
  raw="$(printf '%s' "${raw}" | tr -cd '0-9')"
  if [[ -z "${raw}" ]]; then
    printf '%s\n' "${fallback}"
    return 0
  fi
  printf '%s\n' "${raw}"
}

orchestration_profile="$(echo "${orchestration_profile}" | tr '[:upper:]' '[:lower:]')"
if [[ "${orchestration_profile}" != "claude-light" ]]; then
  orchestration_profile="codex-full"
fi

text="$(printf '%s\n%s\n' "${title}" "${body}" | tr '[:upper:]' '[:lower:]')"
text_len="$(printf '%s' "${text}" | wc -c | tr -d ' ')"
labels_lc="$(printf '%s' "${labels_csv}" | tr '[:upper:]' '[:lower:]')"

risk_score=0
risk_reasons=()

has_label() {
  local label
  label="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ ",${labels_lc}," == *",${label},"* ]]
}

if has_label "large-refactor"; then
  risk_score=$((risk_score + 4))
  risk_reasons+=("large-refactor-label")
fi

if echo "${text}" | grep -Eqi '(migration|rewrite|全面刷新|アーキテクチャ刷新|schema[[:space:]]+change|breaking[[:space:]]+change|incident|障害|root cause|rollback|auth|payment|security)'; then
  risk_score=$((risk_score + 3))
  risk_reasons+=("high-risk-keywords")
fi

if echo "${text}" | grep -Eqi '(workflow|ci|gha|integration|database|concurrency|performance|refactor|infra|deploy|release|運用|本番)'; then
  risk_score=$((risk_score + 1))
  risk_reasons+=("medium-risk-keywords")
fi

if [[ "${has_implement}" == "true" ]]; then
  risk_score=$((risk_score + 1))
  risk_reasons+=("implement-request")
fi

if (( text_len > 1800 )); then
  risk_score=$((risk_score + 2))
  risk_reasons+=("long-spec")
elif (( text_len > 900 )); then
  risk_score=$((risk_score + 1))
  risk_reasons+=("mid-spec")
fi

risk_tier="low"
if (( risk_score >= 5 )); then
  risk_tier="high"
elif (( risk_score >= 2 )); then
  risk_tier="medium"
fi

multi_agent_mode_hint="enhanced"
case "${risk_tier}" in
  low)
    multi_agent_mode_hint="standard"
    ;;
  medium)
    multi_agent_mode_hint="enhanced"
    ;;
  high)
    multi_agent_mode_hint="max"
    ;;
esac

preflight_cycles_floor=3
implementation_dialogue_rounds_floor=2
if [[ "${orchestration_profile}" == "claude-light" ]]; then
  case "${risk_tier}" in
    low)
      preflight_cycles_floor=1
      implementation_dialogue_rounds_floor=1
      ;;
    medium)
      preflight_cycles_floor=2
      implementation_dialogue_rounds_floor=1
      ;;
    high)
      preflight_cycles_floor=3
      implementation_dialogue_rounds_floor=2
      ;;
  esac
else
  case "${risk_tier}" in
    low)
      preflight_cycles_floor=3
      implementation_dialogue_rounds_floor=1
      ;;
    medium)
      preflight_cycles_floor=3
      implementation_dialogue_rounds_floor=2
      ;;
    high)
      preflight_cycles_floor=4
      implementation_dialogue_rounds_floor=3
      ;;
  esac
fi

correction_signal="false"
if has_label "user-corrected" || has_label "postmortem" || has_label "regression" || has_label "incident"; then
  correction_signal="true"
elif echo "${text}" | grep -Eqi '(user[[:space:]-]*correction|postmortem|lessons learned|再発防止|修正依頼|回顧|振り返り|根本原因)'; then
  correction_signal="true"
fi

lessons_required="false"
if [[ "${correction_signal}" == "true" ]]; then
  lessons_required="true"
fi

context_budget_initial=6
context_budget_max=12
case "${risk_tier}" in
  low)
    context_budget_initial=6
    context_budget_max=12
    ;;
  medium)
    context_budget_initial=8
    context_budget_max=16
    ;;
  high)
    context_budget_initial=10
    context_budget_max=20
    ;;
esac

context_budget_floor_initial="$(parse_non_negative_int "${FUGUE_CONTEXT_BUDGET_MIN_INITIAL:-6}" "6")"
context_budget_floor_max="$(parse_non_negative_int "${FUGUE_CONTEXT_BUDGET_MIN_MAX:-12}" "12")"
context_budget_floor_span="$(parse_non_negative_int "${FUGUE_CONTEXT_BUDGET_MIN_SPAN:-6}" "6")"

if (( context_budget_floor_initial < 6 )); then
  context_budget_floor_initial=6
fi
if (( context_budget_floor_max < 12 )); then
  context_budget_floor_max=12
fi
if (( context_budget_floor_span < 4 )); then
  context_budget_floor_span=4
fi
if (( context_budget_floor_max < context_budget_floor_initial )); then
  context_budget_floor_max="${context_budget_floor_initial}"
fi

context_budget_guard_applied="false"
context_budget_guard_reasons=()

if (( context_budget_initial < context_budget_floor_initial )); then
  context_budget_initial="${context_budget_floor_initial}"
  context_budget_guard_applied="true"
  context_budget_guard_reasons+=("raised-initial-floor")
fi

if (( context_budget_max < context_budget_floor_max )); then
  context_budget_max="${context_budget_floor_max}"
  context_budget_guard_applied="true"
  context_budget_guard_reasons+=("raised-max-floor")
fi

if (( context_budget_max < context_budget_initial )); then
  context_budget_max="${context_budget_initial}"
  context_budget_guard_applied="true"
  context_budget_guard_reasons+=("max-not-below-initial")
fi

if (( (context_budget_max - context_budget_initial) < context_budget_floor_span )); then
  context_budget_max=$((context_budget_initial + context_budget_floor_span))
  context_budget_guard_applied="true"
  context_budget_guard_reasons+=("raised-span-floor")
fi

risk_reason_string="none"
if (( ${#risk_reasons[@]} > 0 )); then
  risk_reason_string="$(IFS=,; echo "${risk_reasons[*]}")"
fi

context_budget_guard_reason_string="none"
if (( ${#context_budget_guard_reasons[@]} > 0 )); then
  context_budget_guard_reason_string="$(IFS=,; echo "${context_budget_guard_reasons[*]}")"
fi

emit() {
  local key="$1"
  local val="$2"
  printf '%s=%q\n' "${key}" "${val}"
}

emit risk_tier "${risk_tier}"
emit risk_score "${risk_score}"
emit risk_reasons "${risk_reason_string}"
emit multi_agent_mode_hint "${multi_agent_mode_hint}"
emit preflight_cycles_floor "${preflight_cycles_floor}"
emit implementation_dialogue_rounds_floor "${implementation_dialogue_rounds_floor}"
emit correction_signal "${correction_signal}"
emit lessons_required "${lessons_required}"
emit context_budget_initial "${context_budget_initial}"
emit context_budget_max "${context_budget_max}"
emit context_budget_floor_initial "${context_budget_floor_initial}"
emit context_budget_floor_max "${context_budget_floor_max}"
emit context_budget_floor_span "${context_budget_floor_span}"
emit context_budget_guard_applied "${context_budget_guard_applied}"
emit context_budget_guard_reasons "${context_budget_guard_reason_string}"
