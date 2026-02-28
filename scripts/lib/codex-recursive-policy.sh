#!/usr/bin/env bash
set -euo pipefail

# Resolve whether codex recursive delegation (parent -> child -> grandchild)
# should run for a given lane.

enabled="false"
provider=""
lane=""
depth="3"
target_lanes="codex-main-orchestrator,codex-orchestration-assist"
dry_run="false"
format="env"

usage() {
  cat <<'EOF'
Usage: codex-recursive-policy.sh [options]

Options:
  --enabled VALUE        true|false
  --provider VALUE       codex|claude|glm|gemini|xai
  --lane VALUE           lane name (e.g. codex-main-orchestrator)
  --depth VALUE          recursive depth, minimum 2 (default: 3)
  --target-lanes VALUE   comma-separated lane names or "all"
  --dry-run VALUE        true|false (force synthetic recursive output)
  --format VALUE         env (default) | json
EOF
}

lower_trim() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

is_truthy() {
  local v
  v="$(lower_trim "$1")"
  [[ "${v}" == "1" || "${v}" == "true" || "${v}" == "yes" || "${v}" == "on" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enabled)
      enabled="${2:-false}"
      shift 2
      ;;
    --provider)
      provider="${2:-}"
      shift 2
      ;;
    --lane)
      lane="${2:-}"
      shift 2
      ;;
    --depth)
      depth="${2:-3}"
      shift 2
      ;;
    --target-lanes)
      target_lanes="${2:-codex-main-orchestrator,codex-orchestration-assist}"
      shift 2
      ;;
    --dry-run)
      dry_run="${2:-false}"
      shift 2
      ;;
    --format)
      format="${2:-env}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

provider="$(lower_trim "${provider}")"
lane="$(echo "${lane}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
target_lanes="$(echo "${target_lanes}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

if ! [[ "${depth}" =~ ^[0-9]+$ ]]; then
  depth="3"
fi
if (( depth < 2 )); then
  depth="2"
fi

enabled_norm="false"
if is_truthy "${enabled}"; then
  enabled_norm="true"
fi
dry_run_norm="false"
if is_truthy "${dry_run}"; then
  dry_run_norm="true"
fi

lane_allowed="false"
lane_reason="lane-not-targeted"
if [[ "${target_lanes}" == "all" ]]; then
  lane_allowed="true"
  lane_reason="target-all"
else
  IFS=',' read -r -a lane_rules <<< "${target_lanes}"
  for raw_rule in "${lane_rules[@]}"; do
    rule="$(echo "${raw_rule}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -n "${rule}" ]] || continue
    if [[ "${lane}" == "${rule}" ]]; then
      lane_allowed="true"
      lane_reason="target-match"
      break
    fi
  done
fi

active="false"
reason="disabled"
if [[ "${enabled_norm}" == "true" && "${provider}" == "codex" && "${lane_allowed}" == "true" ]]; then
  active="true"
  reason="${lane_reason}"
elif [[ "${enabled_norm}" != "true" ]]; then
  reason="flag-disabled"
elif [[ "${provider}" != "codex" ]]; then
  reason="provider-not-codex"
else
  reason="${lane_reason}"
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg enabled "${enabled_norm}" \
    --arg active "${active}" \
    --arg provider "${provider}" \
    --arg lane "${lane}" \
    --arg reason "${reason}" \
    --arg lane_allowed "${lane_allowed}" \
    --arg target_lanes "${target_lanes}" \
    --arg depth "${depth}" \
    --arg dry_run "${dry_run_norm}" \
    '{
      enabled:($enabled=="true"),
      active:($active=="true"),
      provider:$provider,
      lane:$lane,
      reason:$reason,
      lane_allowed:($lane_allowed=="true"),
      target_lanes:$target_lanes,
      depth:($depth|tonumber),
      dry_run:($dry_run=="true")
    }'
  exit 0
fi

printf 'recursive_enabled=%q\n' "${enabled_norm}"
printf 'recursive_active=%q\n' "${active}"
printf 'recursive_provider=%q\n' "${provider}"
printf 'recursive_lane=%q\n' "${lane}"
printf 'recursive_reason=%q\n' "${reason}"
printf 'recursive_lane_allowed=%q\n' "${lane_allowed}"
printf 'recursive_target_lanes=%q\n' "${target_lanes}"
printf 'recursive_depth=%q\n' "${depth}"
printf 'recursive_dry_run=%q\n' "${dry_run_norm}"
