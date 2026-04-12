#!/usr/bin/env bash
set -euo pipefail

# validate-agent-matrix.sh — Validate build-agent-matrix.sh output JSON.
#
# Usage:
#   validate-agent-matrix.sh --matrix "${matrix}" --lanes "${lanes}" \
#       --main-signal-lane "${main_signal_lane}" [--min-lanes 6]
#
# Exits 0 if valid, 1 with diagnostic on stderr if invalid.

matrix=""
lanes=""
main_signal_lane=""
min_lanes="${FUGUE_MIN_CONSENSUS_LANES:-6}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --matrix) matrix="${2:-}"; shift 2 ;;
    --lanes) lanes="${2:-}"; shift 2 ;;
    --main-signal-lane) main_signal_lane="${2:-}"; shift 2 ;;
    --min-lanes) min_lanes="${2:-6}"; shift 2 ;;
    *) echo "validate-agent-matrix: unknown arg: $1" >&2; exit 1 ;;
  esac
done

errors=()

# 1. Matrix must be valid JSON with .include array.
if ! echo "${matrix}" | jq -e '.include | type == "array"' >/dev/null 2>&1; then
  errors+=("matrix is not valid JSON or missing .include array")
fi

# 2. Lanes count must be a positive integer.
if ! [[ "${lanes}" =~ ^[0-9]+$ ]] || [[ "${lanes}" -lt 1 ]]; then
  errors+=("lanes is not a positive integer: '${lanes}'")
fi

# 3. Minimum lane enforcement.
if [[ "${lanes}" =~ ^[0-9]+$ ]] && [[ "${lanes}" -lt "${min_lanes}" ]]; then
  errors+=("lanes=${lanes} below minimum=${min_lanes}")
fi

# 4. Lanes count must match actual array length.
if echo "${matrix}" | jq -e '.include | type == "array"' >/dev/null 2>&1; then
  actual="$(echo "${matrix}" | jq -r '.include | length')"
  if [[ "${actual}" != "${lanes}" ]]; then
    errors+=("lanes count mismatch: declared=${lanes} actual=${actual}")
  fi
fi

# 5. Each lane must have required fields.
if echo "${matrix}" | jq -e '.include | type == "array"' >/dev/null 2>&1; then
  invalid_lanes="$(echo "${matrix}" | jq -r '
    .include | to_entries[] |
    select(
      (.value.name | type != "string" or length == 0) or
      (.value.provider | type != "string" or length == 0) or
      (.value.api_url | type != "string" or length == 0) or
      (.value.model | type != "string" or length == 0) or
      (.value.agent_role | type != "string" or length == 0)
    ) | "lane[\(.key)]: missing required field (name/provider/api_url/model/agent_role)"
  ')"
  if [[ -n "${invalid_lanes}" ]]; then
    while IFS= read -r line; do
      errors+=("${line}")
    done <<< "${invalid_lanes}"
  fi
fi

# 6. Provider must be one of known values.
if echo "${matrix}" | jq -e '.include | type == "array"' >/dev/null 2>&1; then
  unknown_providers="$(echo "${matrix}" | jq -r '
    .include[] |
    select(.provider | IN("codex","claude","glm","gemini","xai") | not) |
    "unknown provider: \(.provider) in lane \(.name)"
  ')"
  if [[ -n "${unknown_providers}" ]]; then
    while IFS= read -r line; do
      errors+=("${line}")
    done <<< "${unknown_providers}"
  fi
fi

# 7. Main signal lane must exist in matrix.
if [[ -n "${main_signal_lane}" ]] && echo "${matrix}" | jq -e '.include | type == "array"' >/dev/null 2>&1; then
  found="$(echo "${matrix}" | jq -r --arg name "${main_signal_lane}" '.include[] | select(.name == $name) | .name')"
  if [[ -z "${found}" ]]; then
    errors+=("main_signal_lane '${main_signal_lane}' not found in matrix")
  fi
fi

# 8. No duplicate lane names.
if echo "${matrix}" | jq -e '.include | type == "array"' >/dev/null 2>&1; then
  dupes="$(echo "${matrix}" | jq -r '.include | [.[].name] | group_by(.) | map(select(length > 1) | .[0]) | .[]')"
  if [[ -n "${dupes}" ]]; then
    errors+=("duplicate lane names: ${dupes}")
  fi
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "validate-agent-matrix: FAIL — ${#errors[@]} error(s):" >&2
  for err in "${errors[@]}"; do
    echo "  - ${err}" >&2
  done
  exit 1
fi

echo "validate-agent-matrix: OK (${lanes} lanes, main=${main_signal_lane})"
exit 0
