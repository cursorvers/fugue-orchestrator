#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CALLER="${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml"
IMPLEMENT="${ROOT_DIR}/.github/workflows/fugue-codex-implement.yml"

check() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if rg -q "${pattern}" "${file}"; then
    echo "PASS [${label}]"
  else
    echo "FAIL [${label}]"
    exit 1
  fi
}

check_prepare_allows_vote_command() {
  local file="$1"
  local prepare_line
  prepare_line="$(rg -n '^  prepare:$' "${file}" | head -n1 | cut -d: -f1 || true)"
  if [[ -z "${prepare_line}" ]]; then
    echo "FAIL [implement-prepare-allows-vote-command]"
    exit 1
  fi
  if sed -n "$((prepare_line + 1))p" "${file}" | rg -q "if: \\$\\{\\{ inputs\\.vote_command != 'true' \\}\\}"; then
    echo "FAIL [implement-prepare-allows-vote-command]"
    exit 1
  fi
  echo "PASS [implement-prepare-allows-vote-command]"
}

echo "=== /vote implement continuity checks ==="

check "caller-passes-vote-command-to-implement-workflow" 'vote_command: "\$\{\{ needs\.ctx\.outputs\.vote_command \}\}"' "${CALLER}"
check "caller-passes-implement-request-to-implement-workflow" 'implement_request: "\$\{\{ needs\.ctx\.outputs\.has_implement_request \}\}"' "${CALLER}"
check "caller-passes-implement-confirmed-to-implement-workflow" 'implement_confirmed: "\$\{\{ needs\.ctx\.outputs\.has_implement_confirmed \}\}"' "${CALLER}"
check "caller-passes-council-force-missing-provider" 'council_force_missing_provider: "\$\{\{ github\.event\.inputs\.council_force_missing_provider \|\| '\''none'\'' \}\}"' "${CALLER}"
check "caller-forwards-copilot-secret" '^      COPILOT_GITHUB_TOKEN: \$\{\{ secrets\.COPILOT_GITHUB_TOKEN \}\}' "${CALLER}"
check "caller-forwards-fugue-copilot-secret" '^      FUGUE_COPILOT_TOKEN: \$\{\{ secrets\.FUGUE_COPILOT_TOKEN \}\}' "${CALLER}"
check "caller-forwards-zai-secret" '^      ZAI_API_KEY: \$\{\{ secrets\.ZAI_API_KEY \}\}' "${CALLER}"
check "caller-forwards-gemini-secret" '^      GEMINI_API_KEY: \$\{\{ secrets\.GEMINI_API_KEY \}\}' "${CALLER}"
check "caller-forwards-xai-secret" '^      XAI_API_KEY: \$\{\{ secrets\.XAI_API_KEY \}\}' "${CALLER}"
check "implement-workflow-input" '^      vote_command:' "${IMPLEMENT}"
check "implement-workflow-implement-request-input" '^      implement_request:' "${IMPLEMENT}"
check "implement-workflow-implement-confirmed-input" '^      implement_confirmed:' "${IMPLEMENT}"
check "implement-workflow-council-force-missing-provider-input" '^      council_force_missing_provider:' "${IMPLEMENT}"
check "implement-workflow-copilot-secret" '^      COPILOT_GITHUB_TOKEN:' "${IMPLEMENT}"
check "implement-workflow-fugue-copilot-secret" '^      FUGUE_COPILOT_TOKEN:' "${IMPLEMENT}"
check "implement-workflow-zai-secret" '^      ZAI_API_KEY:' "${IMPLEMENT}"
check "implement-workflow-gemini-secret" '^      GEMINI_API_KEY:' "${IMPLEMENT}"
check "implement-workflow-xai-secret" '^      XAI_API_KEY:' "${IMPLEMENT}"
check_prepare_allows_vote_command "${IMPLEMENT}"
check "implement-runs-on-guard-selected-runner" 'runs-on: \$\{\{ fromJSON\(needs\.credential-guard\.outputs\.runner_json\) \}\}' "${IMPLEMENT}"
check "implement-job-uses-always-with-optional-preflights" "if: \\$\\{\\{ always\\(\\) && needs\\.prepare\\.outputs\\.should_run == 'true'" "${IMPLEMENT}"
check "implement-allows-skipped-optional-preflights" "needs\\.workspace-preflight\\.result != 'failure' && needs\\.workspace-preflight\\.result != 'cancelled' && needs\\.freee-preflight\\.result != 'failure' && needs\\.freee-preflight\\.result != 'cancelled'" "${IMPLEMENT}"
check "implement-guard-has-runner-json-output" 'runner_json: \$\{\{ steps\.guard\.outputs\.runner_json \}\}' "${IMPLEMENT}"
check "implement-guard-normalizes-subscription-runner-label" 'SUBSCRIPTION_RUNNER_LABEL: \$\{\{ vars\.FUGUE_SUBSCRIPTION_RUNNER_LABEL \|\| '\''fugue-subscription'\'' \}\}' "${IMPLEMENT}"
check "implement-guard-routes-backup-heavy-to-ubuntu" 'runner_json='\''"ubuntu-latest"'\''' "${IMPLEMENT}"
check "implement-guard-routes-primary-to-self-hosted-label" 'runner_json="\$\(jq -cn --arg label "\$\{subscription_runner_label\}" '\''\["self-hosted",\$label\]'\''\)"' "${IMPLEMENT}"
check "implement-ensures-copilot-cli" 'Ensure Copilot CLI continuity path' "${IMPLEMENT}"
check "implement-requires-copilot-cli" 'Require Copilot CLI continuity path' "${IMPLEMENT}"
check "implement-has-kernel-preflight-council" 'Run /vote kernel council preflight' "${IMPLEMENT}"
check "implement-has-kernel-final-council" 'Run /vote kernel council final review' "${IMPLEMENT}"
check "implement-uses-kernel-council-helper" 'run-kernel-council-review\.sh' "${IMPLEMENT}"
check "implement-wires-copilot-env-into-council" 'HAS_COPILOT_CLI: \$\{\{ steps\.copilot\.outputs\.available \|\| '\''false'\'' \}\}' "${IMPLEMENT}"
check "implement-wires-force-missing-provider-into-council" 'COUNCIL_FORCE_MISSING_PROVIDER: \$\{\{ inputs\.council_force_missing_provider \|\| '\''none'\'' \}\}' "${IMPLEMENT}"
check "implement-normalizes-implement-request-override" 'INPUT_IMPLEMENT_REQUEST="\$\(echo "\$\{\{ inputs\.implement_request \}\}" \| tr' "${IMPLEMENT}"
check "implement-applies-implement-request-override" 'HAS_IMPLEMENT="\$\{INPUT_IMPLEMENT_REQUEST\}"' "${IMPLEMENT}"
check "implement-normalizes-implement-confirmed-override" 'INPUT_IMPLEMENT_CONFIRMED="\$\(echo "\$\{\{ inputs\.implement_confirmed \}\}" \| tr' "${IMPLEMENT}"
check "implement-applies-implement-confirmed-override" 'HAS_IMPLEMENT_CONFIRMED="\$\{INPUT_IMPLEMENT_CONFIRMED\}"' "${IMPLEMENT}"
check "implement-wires-gemini-env-into-council" 'GEMINI_API_KEY: \$\{\{ secrets\.GEMINI_API_KEY \}\}' "${IMPLEMENT}"
check "implement-wires-xai-env-into-council" 'XAI_API_KEY: \$\{\{ secrets\.XAI_API_KEY \}\}' "${IMPLEMENT}"
check "implement-forces-copilot-continuity-in-council" 'COUNCIL_FORCE_COPILOT_CONTINUITY: "true"' "${IMPLEMENT}"
check "implement-disables-direct-claude-gate-for-gha-copilot" 'STRICT_OPUS_ASSIST_DIRECT: "false"' "${IMPLEMENT}"
if rg -q 'missing-openai-api-key' "${IMPLEMENT}"; then
  echo "FAIL [implement-no-openai-hard-guard]"
  exit 1
fi
echo "PASS [implement-no-openai-hard-guard]"
if rg -q '^  vote-command-guard:' "${IMPLEMENT}" || rg -q '^  vote-command-implement-blocked:' "${CALLER}"; then
  echo "FAIL [legacy-vote-block-removed]"
  exit 1
fi
echo "PASS [legacy-vote-block-removed]"

if rg -q 'codex login --with-api-key' "${IMPLEMENT}"; then
  echo "FAIL [legacy-codex-api-login-removed]"
  exit 1
fi
echo "PASS [legacy-codex-api-login-removed]"

if rg -q '^      OPENAI_API_KEY:$|^      ANTHROPIC_API_KEY:$' "${IMPLEMENT}"; then
  echo "FAIL [implement-no-unused-api-secret-surface]"
  exit 1
fi
echo "PASS [implement-no-unused-api-secret-surface]"

if ! rg -q 'subscription-agent-runner\.sh|--engine subscription' "${ROOT_DIR}/scripts/harness/run-kernel-council-review.sh"; then
  echo "FAIL [kernel-council-helper-subscription-mode]"
  exit 1
fi
echo "PASS [kernel-council-helper-subscription-mode]"

if rg -q 'ci-agent-runner\.sh|--engine api' "${ROOT_DIR}/scripts/harness/run-kernel-council-review.sh"; then
  echo "FAIL [kernel-council-helper-no-api-mode]"
  exit 1
fi
echo "PASS [kernel-council-helper-no-api-mode]"

echo "=== Results: 45/45 passed, 0 failed ==="
