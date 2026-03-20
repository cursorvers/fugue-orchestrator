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
status_comment_file=""

append_summary() {
  local line="${1:-}"
  printf '%s\n' "${line}"
  if [[ -n "${summary_file}" ]]; then
    printf '%s\n' "${line}" >> "${summary_file}"
  fi
  if [[ -n "${status_comment_file}" ]]; then
    printf '%s\n' "${line}" >> "${status_comment_file}"
  fi
}

gh_var_default() {
  local name="$1"
  local fallback="$2"
  local value
  value="$(fugue_gh_retry 3 gh variable get "${name}" --repo "${repo}" --json value -q '.value' || true)"
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

current_run_url() {
  local server_url="${GITHUB_SERVER_URL:-https://github.com}"
  local run_id="${GITHUB_RUN_ID:-}"
  if [[ -z "${run_id}" ]]; then
    return 0
  fi
  printf '%s/%s/actions/runs/%s\n' "${server_url}" "${repo}" "${run_id}"
}

ensure_status_issue() {
  local status_issue
  status_issue="$(fugue_gh_retry 4 gh issue list --repo "${repo}" --state open --label "fugue-status" --limit 1 --json number --jq '.[0].number // empty' || true)"
  if [[ -n "${status_issue}" ]]; then
    printf '%s\n' "${status_issue}"
    return 0
  fi

  fugue_gh_retry 4 gh label create "fugue-status" \
    --repo "${repo}" \
    --description "Status reporting thread for FUGUE orchestration" \
    --color "1D76DB" >/dev/null 2>&1 || true

  status_issue_url="$(
    fugue_gh_retry 4 gh issue create --repo "${repo}" \
      --title "FUGUE Status Thread" \
      --label "fugue-status" \
      --body "Automated status and mobile progress reports are posted here."
  )"
  printf '%s\n' "${status_issue_url##*/}"
}

latest_workflow_run_json() {
  local workflow_name="$1"
  (
    fugue_gh_api_retry "repos/${repo}/actions/runs?per_page=100" 4 || echo '{"workflow_runs":[]}'
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
        fugue_gh_api_retry "repos/${repo}/actions/runs?per_page=100" 4 || echo '{"workflow_runs":[]}'
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

  runner_json="$(fugue_gh_api_retry "repos/${repo}/actions/runners?per_page=100" 4 || echo '{}')"
  runner_online_count="$(printf '%s' "${runner_json}" | jq -r --arg label "${runner_label}" '[.runners[]? | select(.status=="online" and .busy != true and ([.labels[]?.name] | index("self-hosted") != null) and ([.labels[]?.name] | index($label) != null))] | length' 2>/dev/null || echo "0")"

  pending_json="$(fugue_gh_retry 4 gh issue list --repo "${repo}" --state open --label "fugue-task" --limit 200 --json number,labels || echo '[]')"
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

append_active_issue_summary() {
  local issues_json issue_lines line_count
  issues_json="$(fugue_gh_retry 4 gh issue list --repo "${repo}" --state open --label "fugue-task" --limit 10 --json number,title,updatedAt,url,labels || echo '[]')"
  append_summary ""
  append_summary "### Active fugue-task issues"
  line_count="$(printf '%s' "${issues_json}" | jq -r 'length')"
  if [[ "${line_count}" == "0" ]]; then
    append_summary "- none"
    return 0
  fi
  while IFS= read -r issue_line; do
    append_summary "${issue_line}"
  done < <(
    printf '%s' "${issues_json}" | jq -r '
      .[]
      | "- [#\(.number)](\(.url)) \(.title) — labels: \(([.labels[]?.name] | join(",")) // "none") — updated: \(.updatedAt // "n/a")"
    '
  )
}

mobile_progress() {
  local status_issue
  status_comment_file="$(mktemp)"
  status_issue="$(ensure_status_issue)"

  append_summary "## Kernel Mobile Progress Snapshot"
  append_summary ""
  append_summary "- repository: \`${repo}\`"
  append_summary "- generated from: [kernel-recovery-console]($(current_run_url))"
  append_summary "- mode: \`mobile-progress\`"

  summarize_status
  append_active_issue_summary

  append_summary ""
  append_summary "### Mobile usage"
  append_summary "- Use this thread for quick status checks from GitHub Mobile."
  append_summary "- For recovery actions, run \`kernel-recovery-console\` with \`continuity-canary\`, \`rollback-canary\`, or \`reroute-issue\`."

  fugue_gh_retry 4 gh issue comment "${status_issue}" --repo "${repo}" --body-file "${status_comment_file}" >/dev/null
  append_summary ""
  append_summary "- posted snapshot to [fugue-status issue #${status_issue}](https://github.com/${repo}/issues/${status_issue})"
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

  if ! fugue_gh_retry 4 gh workflow run "${workflow_file}" --repo "${repo}" "$@" >/dev/null; then
    append_summary "- dispatch \`${workflow_file}\`: failed to queue workflow dispatch"
    return 1
  fi
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

load_reconcile_claim_state() {
  if gh variable list --repo "${repo}" >/dev/null 2>&1; then
    gh api "repos/${repo}/actions/variables/FUGUE_RECONCILE_CLAIM_STATE" --jq '.value' 2>/dev/null || printf '{}'
  else
    printf '{}'
  fi
}

persist_reconcile_claim_state() {
  local state_json="$1"
  if gh variable list --repo "${repo}" >/dev/null 2>&1; then
    gh variable set FUGUE_RECONCILE_CLAIM_STATE --repo "${repo}" --body "${state_json}" >/dev/null 2>&1 || true
  fi
}

reroute_issue() {
  local issue_json labels_json has_tutti has_processing has_fugue
  local claim_state claim_env dispatch_issue_numbers_json dispatch_count next_state_json
  local state_update_required persist_state_effective failed_issue_numbers_json persist_json
  if [[ -z "${issue_number}" ]]; then
    echo "RECOVERY_ISSUE_NUMBER is required for reroute-issue" >&2
    exit 1
  fi

  issue_json="$(fugue_gh_api_retry "repos/${repo}/issues/${issue_number}" 4)"
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

  claim_state="$(load_reconcile_claim_state)"
  claim_env="$(
    bash "${SCRIPT_DIR}/../lib/watchdog-reconcile-claim-policy.sh" \
      --pending-json "[${issue_number}]" \
      --previous-state-json "${claim_state}" \
      --persist-state true \
      --now-epoch "$(date +%s)" \
      --ttl-seconds 1800 \
      --format env
  )"
  while IFS= read -r _line; do
    case "$_line" in
      dispatch_count=*|state_update_required=*|persist_state=*|next_state_json=*) eval "$_line" ;;
    esac
  done <<< "${claim_env}"

  if [[ "${dispatch_count}" == "0" ]]; then
    append_summary "- reconcile claim: active claim already exists; reroute skipped"
    return 0
  fi

  failed_issue_numbers_json='[]'
  if [[ "${has_tutti}" == "true" || "${has_processing}" == "true" || "${has_fugue}" == "true" ]]; then
    if ! dispatch_workflow \
      "fugue-caller.yml" \
      -f issue_number="${issue_number}" \
      -f trigger_event_name=issues \
      -f trigger_label_name=tutti \
      -f trust_subject="${trust_subject}" \
      -f allow_processing_rerun=true \
      -f subscription_offline_policy_override="${offline_policy}" \
      -f handoff_target="${handoff_target}"; then
      failed_issue_numbers_json="[${issue_number}]"
    fi
    if [[ "${state_update_required}" == "true" && "${persist_state}" == "true" ]]; then
      persist_json="$(jq -cn \
        --argjson state "${next_state_json}" \
        --argjson failed "${failed_issue_numbers_json}" '
          reduce $failed[] as $issue ($state; .claims |= (del(.[($issue|tostring)])))
        ')"
      persist_reconcile_claim_state "${persist_json}"
    fi
    return 0
  fi

  append_summary "- no recovery dispatch performed: issue is not labeled \`fugue-task\`"
}

case "${mode}" in
  status)
    summarize_status
    ;;
  mobile-progress)
    mobile_progress
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
