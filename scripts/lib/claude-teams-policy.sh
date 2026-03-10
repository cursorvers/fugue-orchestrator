#!/usr/bin/env bash
set -euo pipefail

task_size_tier=""
risk_tier=""
claude_state=""
title=""
body=""
format="env"

usage() {
  cat <<'EOF'
Usage: claude-teams-policy.sh [options]

Options:
  --task-size-tier <small|medium|large|critical>
  --risk-tier <low|medium|high>
  --claude-state <ok|degraded|exhausted>
  --title <text>
  --body <text>
  --format <env|json>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-size-tier)
      task_size_tier="${2:-}"
      shift 2
      ;;
    --risk-tier)
      risk_tier="${2:-}"
      shift 2
      ;;
    --claude-state)
      claude_state="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --body)
      body="${2:-}"
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

task_size_tier="$(echo "${task_size_tier:-small}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${task_size_tier}" != "small" && "${task_size_tier}" != "medium" && "${task_size_tier}" != "large" && "${task_size_tier}" != "critical" ]]; then
  task_size_tier="small"
fi

risk_tier="$(echo "${risk_tier:-low}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${risk_tier}" != "low" && "${risk_tier}" != "medium" && "${risk_tier}" != "high" ]]; then
  risk_tier="low"
fi

claude_state="$(echo "${claude_state:-ok}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_state}" != "ok" && "${claude_state}" != "degraded" && "${claude_state}" != "exhausted" ]]; then
  claude_state="ok"
fi

text="$(printf '%s\n%s\n' "${title}" "${body}" | tr '[:upper:]' '[:lower:]')"

member_cap="${FUGUE_CLAUDE_TEAMS_MEMBER_CAP:-3}"
member_cap="$(printf '%s' "${member_cap}" | tr -cd '0-9')"
if [[ -z "${member_cap}" ]]; then
  member_cap="3"
fi
if (( 10#${member_cap} < 2 )); then
  member_cap="2"
elif (( 10#${member_cap} > 4 )); then
  member_cap="4"
fi

max_invocations="${FUGUE_CLAUDE_TEAMS_MAX_INVOCATIONS:-1}"
max_invocations="$(printf '%s' "${max_invocations}" | tr -cd '0-9')"
if [[ -z "${max_invocations}" || 10#${max_invocations} != 1 ]]; then
  max_invocations="1"
fi

force_enable="$(echo "${FUGUE_CLAUDE_TEAMS_FORCE_ENABLE:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${force_enable}" != "true" ]]; then
  force_enable="false"
fi

allow="false"
reason="task-not-large-enough"
collaboration_signal="false"

if echo "${text}" | grep -Eqi '(cross-layer|cross repo|cross-repo|incident|root cause|multi repo|multi-repo|skill chain|claude-native|obsidian|note manuscript|slide|design chain|connector|integration debugging|conflicting hypotheses|調査|切り分け|横断|連携|接続|根本原因|障害解析|複数仮説)'; then
  collaboration_signal="true"
fi

if [[ "${force_enable}" == "true" ]]; then
  allow="true"
  reason="force-enabled"
elif [[ "${task_size_tier}" != "large" && "${task_size_tier}" != "critical" ]]; then
  allow="false"
  reason="task-not-large-enough"
elif [[ "${claude_state}" != "ok" ]]; then
  allow="false"
  reason="claude-state-${claude_state}"
elif [[ "${collaboration_signal}" != "true" ]]; then
  allow="false"
  reason="no-collaboration-signal"
elif [[ "${risk_tier}" == "low" ]]; then
  allow="false"
  reason="risk-too-low"
else
  allow="true"
  reason="large-task-collaboration-signal"
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg allowed "${allow}" \
    --arg reason "${reason}" \
    --arg collaboration_signal "${collaboration_signal}" \
    --arg task_size_tier "${task_size_tier}" \
    --arg risk_tier "${risk_tier}" \
    --arg claude_state "${claude_state}" \
    --arg member_cap "${member_cap}" \
    --arg max_invocations "${max_invocations}" \
    '{
      claude_teams_allowed:($allowed == "true"),
      claude_teams_reason:$reason,
      collaboration_signal:($collaboration_signal == "true"),
      task_size_tier:$task_size_tier,
      risk_tier:$risk_tier,
      claude_state:$claude_state,
      member_cap:($member_cap|tonumber),
      max_invocations:($max_invocations|tonumber)
    }'
  exit 0
fi

printf 'claude_teams_allowed=%q\n' "${allow}"
printf 'claude_teams_reason=%q\n' "${reason}"
printf 'claude_teams_collaboration_signal=%q\n' "${collaboration_signal}"
printf 'claude_teams_member_cap=%q\n' "${member_cap}"
printf 'claude_teams_max_invocations=%q\n' "${max_invocations}"
