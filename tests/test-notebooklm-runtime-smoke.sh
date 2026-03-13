#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/notebooklm-runtime-smoke.yml"
IMPLEMENT_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-codex-implement.yml"
SYNC_SCRIPT="${ROOT_DIR}/scripts/local/sync-gh-secrets-from-env.sh"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/local/bootstrap-prod-secrets.sh"

failures=0

fail() {
  echo "FAIL [$1]" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS [$1]" >&2
}

assert_not_grep() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "${label}"
  else
    pass "${label}"
  fi
}

assert_grep() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq -- "${pattern}" "${file}"; then
    pass "${label}"
  else
    fail "${label}"
  fi
}

assert_grep "${WORKFLOW}" 'name: NotebookLM Runtime Smoke' "workflow exists"
assert_grep "${WORKFLOW}" 'push:' "runtime smoke has push trigger for branch canary"
assert_grep "${WORKFLOW}" 'runs-on:' "workflow has jobs"
assert_grep "${WORKFLOW}" 'subscription_runner_label:' "runtime smoke accepts runner label input"
assert_grep "${WORKFLOW}" 'notebooklm_sensitivity:' "runtime smoke accepts sensitivity input"
assert_grep "${WORKFLOW}" 'notebooklm_nlm_bin:' "runtime smoke accepts CLI path input"
assert_grep "${WORKFLOW}" 'content_hint_applied:' "runtime smoke accepts direct content-hint input"
assert_grep "${WORKFLOW}" 'content_action_hint:' "runtime smoke accepts direct content-action input"
assert_grep "${WORKFLOW}" 'content_skill_hint:' "runtime smoke accepts direct content-skill input"
assert_grep "${WORKFLOW}" 'content_reason:' "runtime smoke accepts direct content-reason input"
assert_grep "${WORKFLOW}" 'issues: read' "runtime smoke uses read-only issue permission"
assert_grep "${WORKFLOW}" 'self-hosted' "runtime smoke uses self-hosted runner"
assert_grep "${WORKFLOW}" 'actions/setup-go@v5' "runtime smoke sets up Go for NotebookLM CLI"
assert_grep "${WORKFLOW}" 'go install github.com/tmc/nlm/cmd/nlm@latest' "runtime smoke installs NotebookLM CLI"
assert_grep "${WORKFLOW}" "scripts/skills/sync-notebooklm-skills.sh" "runtime smoke syncs NotebookLM skills"
assert_grep "${WORKFLOW}" "scripts/check-notebooklm-runtime-readiness.sh" "runtime smoke runs readiness gate"
assert_grep "${WORKFLOW}" 'NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE: "required"' "runtime smoke requires live smoke"
assert_grep "${WORKFLOW}" 'NOTEBOOKLM_READINESS_EXECUTE_LIVE_MODE: "required"' "runtime smoke requires live execution"
assert_grep "${WORKFLOW}" 'secrets.FUGUE_NOTEBOOKLM_AUTH_TOKEN' "runtime smoke wires NotebookLM auth token secret"
assert_grep "${WORKFLOW}" 'secrets.FUGUE_NOTEBOOKLM_COOKIES' "runtime smoke wires NotebookLM cookies secret"
assert_grep "${WORKFLOW}" "scripts/harness/notebooklm-preflight-enrich.sh" "runtime smoke runs NotebookLM preflight"
assert_grep "${WORKFLOW}" 'inputs.notebooklm_runtime_environment' "runtime smoke uses dispatch environment input"
assert_grep "${WORKFLOW}" 'inputs.subscription_runner_label' "runtime smoke uses dispatch runner label input"
assert_grep "${WORKFLOW}" 'inputs.notebooklm_sensitivity' "runtime smoke uses dispatch sensitivity input"
assert_grep "${WORKFLOW}" 'inputs.notebooklm_nlm_bin' "runtime smoke uses dispatch CLI input"
assert_grep "${WORKFLOW}" 'CONTENT_HINT_APPLIED_INPUT:' "runtime smoke passes direct content-hint snapshot"
assert_grep "${WORKFLOW}" 'CONTENT_ACTION_HINT_INPUT:' "runtime smoke passes direct content-action snapshot"
assert_grep "${WORKFLOW}" 'CONTENT_SKILL_HINT_INPUT:' "runtime smoke passes direct content-skill snapshot"
assert_grep "${WORKFLOW}" 'CONTENT_REASON_INPUT:' "runtime smoke passes direct content-reason snapshot"
assert_grep "${WORKFLOW}" "github.event_name == 'push' && '499'" "runtime smoke seeds push canary issue context"
assert_grep "${WORKFLOW}" "github.event_name == 'push' && 'notebooklm-visual-brief'" "runtime smoke seeds push canary NotebookLM hint"
assert_grep "${WORKFLOW}" 'GITHUB_STEP_SUMMARY' "runtime smoke records result in workflow summary"
assert_not_grep "${WORKFLOW}" 'gh issue comment' "runtime smoke does not post issue comments"

assert_grep "${IMPLEMENT_WORKFLOW}" 'Sync NotebookLM skills on self-hosted runner' "implement workflow sync step added"
assert_grep "${IMPLEMENT_WORKFLOW}" 'sync-notebooklm-skills.sh' "implement workflow calls sync script"

assert_grep "${SYNC_SCRIPT}" 'FUGUE_NOTEBOOKLM_RUNTIME_ENV' "sync script exports NotebookLM runtime env variable"
assert_grep "${SYNC_SCRIPT}" 'FUGUE_NOTEBOOKLM_RUNTIME_ENABLED' "sync script exports NotebookLM runtime enabled variable"
assert_grep "${SYNC_SCRIPT}" 'FUGUE_NOTEBOOKLM_REQUIRE_RUNTIME_AUTH' "sync script exports NotebookLM runtime auth variable"
assert_grep "${SYNC_SCRIPT}" 'FUGUE_NOTEBOOKLM_AUTH_TOKEN' "sync script exports NotebookLM auth token secret"
assert_grep "${SYNC_SCRIPT}" 'FUGUE_NOTEBOOKLM_COOKIES' "sync script exports NotebookLM cookies secret"

assert_grep "${BOOTSTRAP_SCRIPT}" 'FUGUE_NOTEBOOKLM_RUNTIME_ENV' "bootstrap script documents NotebookLM env"
assert_grep "${BOOTSTRAP_SCRIPT}" 'FUGUE_NOTEBOOKLM_RUNTIME_ENABLED' "bootstrap script documents NotebookLM runtime enabled"
assert_grep "${BOOTSTRAP_SCRIPT}" 'FUGUE_NOTEBOOKLM_AUTH_TOKEN' "bootstrap script documents NotebookLM auth token"
assert_grep "${BOOTSTRAP_SCRIPT}" 'FUGUE_NOTEBOOKLM_COOKIES' "bootstrap script documents NotebookLM cookies"

echo "PASS [test-notebooklm-runtime-smoke]"

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
