#!/usr/bin/env bash
set -euo pipefail

permission="none"
vote_command="false"
canary_dispatch_owned="false"
issue_title=""
issue_body=""
issue_author=""
format="env"

usage() {
  cat <<'EOF'
Usage: canary-trust-policy.sh [options]

Options:
  --permission <none|read|triage|write|maintain|admin|...>
  --vote-command <true|false>
  --canary-dispatch-owned <true|false>
  --issue-title <text>
  --issue-body <text>
  --issue-author <text>
  --format <env|json>
EOF
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" || "${value}" == "1" || "${value}" == "yes" ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

normalize_canary_actor() {
  local actor
  actor="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${actor}" in
    "github-actions[bot]"|"github-actions"|"app/github-actions")
      printf 'github-actions\n'
      ;;
    *)
      printf '%s\n' "${actor}"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --permission)
      permission="${2:-none}"
      shift 2
      ;;
    --vote-command)
      vote_command="${2:-false}"
      shift 2
      ;;
    --canary-dispatch-owned)
      canary_dispatch_owned="${2:-false}"
      shift 2
      ;;
    --issue-title)
      issue_title="${2:-}"
      shift 2
      ;;
    --issue-body)
      issue_body="${2:-}"
      shift 2
      ;;
    --issue-author)
      issue_author="${2:-}"
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

permission="$(printf '%s' "${permission:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
vote_command="$(normalize_bool "${vote_command}")"
canary_dispatch_owned="$(normalize_bool "${canary_dispatch_owned}")"
issue_author="$(normalize_canary_actor "${issue_author:-}")"

title_matches="false"
body_matches="false"
author_matches="false"
canary_markers_valid="false"
effective_permission="${permission}"
trusted="false"
trust_reason="permission-${permission}"

if printf '%s' "${issue_title}" | grep -Eqi '^\[canary(-lite)?\][[:space:]]'; then
  title_matches="true"
fi
if printf '%s' "${issue_body}" | grep -Eqi '^##[[:space:]]+Canary$|Automated orchestration canary\.'; then
  body_matches="true"
fi
if [[ "${issue_author}" == "github-actions" ]]; then
  author_matches="true"
fi
if [[ "${title_matches}" == "true" && "${body_matches}" == "true" && "${author_matches}" == "true" ]]; then
  canary_markers_valid="true"
fi

if [[ "${canary_dispatch_owned}" == "true" && "${canary_markers_valid}" == "true" ]]; then
  effective_permission="canary-bypass"
  trusted="true"
  trust_reason="canary-owned-dispatch"
elif [[ "${vote_command}" == "true" ]]; then
  trusted="true"
  trust_reason="vote-command"
  if [[ "${effective_permission}" == "none" ]]; then
    effective_permission="vote-bypass"
  fi
elif [[ "${effective_permission}" == "write" || "${effective_permission}" == "maintain" || "${effective_permission}" == "admin" ]]; then
  trusted="true"
  trust_reason="collaborator-permission"
else
  trusted="false"
  if [[ "${canary_dispatch_owned}" == "true" && "${canary_markers_valid}" != "true" ]]; then
    trust_reason="canary-markers-invalid"
  fi
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg permission "${effective_permission}" \
    --arg trusted "${trusted}" \
    --arg trust_reason "${trust_reason}" \
    --arg canary_dispatch_owned "${canary_dispatch_owned}" \
    --arg canary_markers_valid "${canary_markers_valid}" \
    --arg title_matches "${title_matches}" \
    --arg body_matches "${body_matches}" \
    --arg author_matches "${author_matches}" \
    '{
      permission:$permission,
      trusted:($trusted == "true"),
      trust_reason:$trust_reason,
      canary_dispatch_owned:($canary_dispatch_owned == "true"),
      canary_markers_valid:($canary_markers_valid == "true"),
      title_matches:($title_matches == "true"),
      body_matches:($body_matches == "true"),
      author_matches:($author_matches == "true")
    }'
  exit 0
fi

printf 'permission=%q\n' "${effective_permission}"
printf 'trusted=%q\n' "${trusted}"
printf 'trust_reason=%q\n' "${trust_reason}"
printf 'canary_markers_valid=%q\n' "${canary_markers_valid}"
printf 'title_matches=%q\n' "${title_matches}"
printf 'body_matches=%q\n' "${body_matches}"
printf 'author_matches=%q\n' "${author_matches}"
