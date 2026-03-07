#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common-utils.sh"

repo="${GITHUB_REPOSITORY:-}"
mode="$(lower_trim "${RECOVERY_MODE:-status}")"
issue_number="${RECOVERY_ISSUE_NUMBER:-}"
handoff_target="$(lower_trim "${RECOVERY_HANDOFF_TARGET:-kernel}")"
offline_policy="$(lower_trim "${RECOVERY_OFFLINE_POLICY:-continuity}")"
canary_mode="$(lower_trim "${RECOVERY_CANARY_MODE:-lite}")"
trust_subject="${RECOVERY_TRUST_SUBJECT:-${GITHUB_ACTOR:-}}"
dispatch_nonce="${RECOVERY_DISPATCH_NONCE:-$(date -u +%Y%m%d%H%M%S)}"

if [[ -z "${repo}" ]]; then
  echo "GITHUB_REPOSITORY is required" >&2
  exit 1
fi

if [[ "${handoff_target}" != "kernel" && "${handoff_target}" != "fugue-bridge" ]]; then
  handoff_target="kernel"
fi
if [[ "${offline_policy}" != "continuity" && "${offline_policy}" != "hold" && "${offline_policy}" != "inherit" ]]; then
  offline_policy="continuity"
fi
if [[ "${canary_mode}" != "lite" && "${canary_mode}" != "full" ]]; then
  canary_mode="lite"
fi

summary_file="${GITHUB_STEP_SUMMARY:-}"

append_summary() {
  local line="${1:-}"
  printf '%s\n' "${line}"
  if [[ -n "${summary_file}" ]]; then
    printf '%s\n' "${line}" >> "${summary_file}"
  fi
}

gh_retry() {
  local attempts="${1:-3}"
  shift
  local sleep_sec=1
  local i out
  for ((i=1; i<=attempts; i++)); do
    if out="$("$@" 2>/dev/null)"; then
      printf '%s\n' "${out}"
      return 0
    fi
    if (( i == attempts )); then
      return 1
    fi
    sleep "${sleep_sec}"
    if (( sleep_sec < 4 )); then
      sleep_sec=$((sleep_sec * 2))
    fi
  done
  return 1
}

gh_api_retry() {
  local endpoint="$1"
  local attempts="${2:-3}"
  gh_retry "${attempts}" gh api "${endpoint}"
}

gh_var_default() {
  local name="$1"
  local fallback="$2"
  local value
  value="$(gh_retry 3 gh variable get "${name}" --repo "${repo}" --json value -q '.value' || true)"
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${fallback}"
  fi
}

workflow_url() {
  local run_id="${1:-}"
  if [[ -z "${run_id}" ]]; then
    return 0
  fi
  printf 'https://github.com/%s/actions/runs/%s\n' "${repo}" "${run_id}"
}

latest_workflow_run_json() {
  local workflow_name="$1"
  (
    gh_api_retry "repos/${repo}/actions/runs?per_page=100" 4 || echo '{"workflow_runs":[]}'
  ) | jq -c --arg wf "${workflow_name}" '
      [.workflow_runs[]?
        | select((((.path // "") | endswith("/" + $wf)) or ((.path // "") | endswith($wf))))
      ]
      | first
      | if . == null then {}
        else {
          databaseId: .id,
          displayTitle: .display_title,
          event: .event,
          status: .status,
          conclusion: .conclusion,
          url: .html_url,
          createdAt: .created_at,
          workflowName: .name
        } end
    '
}

wait_for_workflow_dispatch_run() {
  local workflow_name="$1"
  local baseline_id="${2:-0}"
  local attempts="${3:-12}"
  local sleep_sec="${4:-5}"
  local candidate candidate_id
  for ((i=1; i<=attempts; i++)); do
    candidate="$(
      (
        gh_api_retry "repos/${repo}/actions/runs?per_page=100" 4 || echo '{"workflow_runs":[]}'
      ) | jq -c --arg wf "${workflow_name}" --argjson baseline "${baseline_id}" '
        [.workflow_runs[]?
          | select(.event == "workflow_dispatch")
          | select((((.path // "") | endswith("/" + $wf)) or ((.path // "") | endswith($wf))))
          | select(.id > $baseline)
        ]
        | first
        | if . == null then {}
          else {
            databaseId: .id,
            displayTitle: .display_title,
            event: .event,
            status: .status,
            conclusion: .conclusion,
            url: .html_url,
            createdAt: .created_at,
            workflowName: .name
          } end
      '
    )"
    candidate_id="$(printf '%s' "${candidate}" | jq -r '.databaseId // 0')"
    if [[ "${candidate_id}" != "0" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    sleep "${sleep_sec}"
  done
  return 1
}

summarize_status() {
  local runner_label claude_state pending_json pending_count processing_count needs_human_count
  local runner_json runner_online_count
  runner_label="$(gh_var_default "FUGUE_SUBSCRIPTION_RUNNER_LABEL" "fugue-subscription")"
  claude_state="$(gh_var_default "FUGUE_CLAUDE_RATE_LIMIT_STATE" "ok")"

  runner_json="$(gh_api_retry "repos/${repo}/actions/runners?per_page=100" 4 || echo '{}')"
  runner_online_count="$(printf '%s' "${runner_json}" | jq -r --arg label "${runner_label}" '[.runners[]? | select(.status=="online" and .busy != true and ([.labels[]?.name] | index("self-hosted") != null) and ([.labels[]?.name] | index($label) != null))] | length' 2>/dev/null || echo "0")"

  pending_json="$(gh_retry 4 gh issue list --repo "${repo}" --state open --label "fugue-task" --limit 200 --json number,labels || echo '[]')"
  pending_count="$(printf '%s' "${pending_json}" | jq -r 'length')"
  processing_count="$(printf '%s' "${pending_json}" | jq -r '[.[] | select((([.labels[]?.name] | index("processing")) != null))] | length')"
  needs_human_count="$(printf '%s' "${pending_json}" | jq -r '[.[] | select((([.labels[]?.name] | index("needs-human")) != null))] | length')"

  append_summary "## Kernel Recovery Status"
  append_summary ""
  append_summary "- repository: \`${repo}\`"
  append_summary "- claude rate-limit state: \`${claude_state}\`"
  append_summary "- subscription runner label: \`${runner_label}\`"
  append_summary "- online self-hosted runners: \`${runner_online_count}\`"
  append_summary "- open fugue-task issues: \`${pending_count}\`"
  append_summary "- processing issues: \`${processing_count}\`"
  append_summary "- needs-human issues: \`${needs_human_count}\`"
  append_summary ""

  for workflow_name in \
    "fugue-orchestrator-canary.yml" \
    "fugue-watchdog.yml" \
    "fugue-task-router.yml" \
    "fugue-tutti-caller.yml"
  do
    run_json="$(latest_workflow_run_json "${workflow_name}")"
    run_id="$(printf '%s' "${run_json}" | jq -r '.databaseId // empty')"
    conclusion="$(printf '%s' "${run_json}" | jq -r '.conclusion // .status // "unknown"')"
    created_at="$(printf '%s' "${run_json}" | jq -r '.createdAt // "n/a"')"
    if [[ -n "${run_id}" ]]; then
      append_summary "- latest \`${workflow_name}\`: [run ${run_id}]($(workflow_url "${run_id}")) \`${conclusion}\` at \`${created_at}\`"
    else
      append_summary "- latest \`${workflow_name}\`: not found"
    fi
  done
}

run_canary_mode() {
  local verify_rollback="$1"
  append_summary "## Kernel Recovery Canary"
  append_summary ""
  append_summary "- mode: \`${mode}\`"
  append_summary "- canary mode: \`${canary_mode}\`"
  append_summary "- offline policy override: \`${offline_policy}\`"
  append_summary "- verify rollback: \`${verify_rollback}\`"
  append_summary ""

  export CANARY_MODE_INPUT="${canary_mode}"
  export CANARY_OFFLINE_POLICY_OVERRIDE="${offline_policy}"
  export CANARY_PRIMARY_HANDOFF_TARGET="kernel"
  export CANARY_VERIFY_ROLLBACK="${verify_rollback}"

  bash "${SCRIPT_DIR}/run-canary.sh"
}

dispatch_workflow() {
  local workflow_file="$1"
  shift
  local baseline_json baseline_id run_json run_id run_url
  baseline_json="$(latest_workflow_run_json "${workflow_file}")"
  baseline_id="$(printf '%s' "${baseline_json}" | jq -r '.databaseId // 0')"

  gh_retry 4 gh workflow run "${workflow_file}" --repo "${repo}" "$@" >/dev/null
  sleep 5

  run_json="$(wait_for_workflow_dispatch_run "${workflow_file}" "${baseline_id}" 18 5 || echo '{}')"
  run_id="$(printf '%s' "${run_json}" | jq -r '.databaseId // 0')"
  run_url="$(printf '%s' "${run_json}" | jq -r '.url // empty')"
  if [[ "${run_id}" == "0" ]]; then
    append_summary "- dispatch \`${workflow_file}\`: queued, run id not yet resolved"
    return 0
  fi
  append_summary "- dispatch \`${workflow_file}\`: [run ${run_id}](${run_url})"
}

reroute_issue() {
  local issue_json labels_json has_tutti has_processing has_fugue
  if [[ -z "${issue_number}" ]]; then
    echo "RECOVERY_ISSUE_NUMBER is required for reroute-issue" >&2
    exit 1
  fi

  issue_json="$(gh_api_retry "repos/${repo}/issues/${issue_number}" 4)"
  labels_json="$(printf '%s' "${issue_json}" | jq -c '[.labels[]?.name]')"
  has_tutti="$(printf '%s' "${labels_json}" | jq -r 'index("tutti") != null')"
  has_processing="$(printf '%s' "${labels_json}" | jq -r 'index("processing") != null')"
  has_fugue="$(printf '%s' "${labels_json}" | jq -r 'index("fugue-task") != null')"

  append_summary "## Kernel Recovery Reroute"
  append_summary ""
  append_summary "- issue: [#${issue_number}](https://github.com/${repo}/issues/${issue_number})"
  append_summary "- labels: \`${labels_json}\`"
  append_summary "- handoff target: \`${handoff_target}\`"
  append_summary "- offline policy override: \`${offline_policy}\`"
  append_summary ""

  if [[ "${has_tutti}" == "true" || "${has_processing}" == "true" ]]; then
    dispatch_workflow \
      "fugue-tutti-caller.yml" \
      -f issue_number="${issue_number}" \
      -f trust_subject="${trust_subject}" \
      -f allow_processing_rerun=true \
      -f subscription_offline_policy_override="${offline_policy}" \
      -f handoff_target="${handoff_target}" \
      -f dispatch_nonce="${dispatch_nonce}"
    return 0
  fi

  if [[ "${has_fugue}" == "true" ]]; then
    dispatch_workflow \
      "fugue-task-router.yml" \
      -f issue_number="${issue_number}"
    return 0
  fi

  append_summary "- no recovery dispatch performed: issue is not labeled \`fugue-task\`"
}

case "${mode}" in
  status)
    summarize_status
    ;;
  continuity-canary)
    run_canary_mode "false"
    ;;
  rollback-canary)
    run_canary_mode "true"
    ;;
  reroute-issue)
    reroute_issue
    ;;
  *)
    echo "Unknown RECOVERY_MODE: ${mode}" >&2
    exit 1
    ;;
esac
