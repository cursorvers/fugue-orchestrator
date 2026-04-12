#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORKERS_HUB_ROOT="${WORKERS_HUB_ROOT:-${ROOT_DIR}/../cloudflare-workers-hub-deploy}"
CURSORVERS_LINE_ROOT="${CURSORVERS_LINE_ROOT:-${ROOT_DIR}/../cursorvers_line_free_dev}"
OUT_DIR="${OUT_DIR:-${HOME}/Dev/tmp/kernel-peripheral-verification}"
ISSUE_NUMBER="${ISSUE_NUMBER:-123}"
ISSUE_REPO="${ISSUE_REPO:-cursorvers/fugue-orchestrator}"
ISSUE_TITLE="${ISSUE_TITLE:-Kernel peripheral smoke}"
ISSUE_BODY="${ISSUE_BODY:-Simulated issue contract for Kernel peripheral verification.}"

usage() {
  cat <<'EOF'
Usage:
  scripts/sim-kernel-peripherals.sh [options]

Options:
  --workers-hub-root <path>      Path to cloudflare-workers-hub-deploy
  --cursorvers-line-root <path>  Path to cursorvers_line_free_dev
  --out-dir <path>               Output directory (default: \$HOME/Dev/tmp/kernel-peripheral-verification)
  --issue-number <n>             Mock issue number for linked-system smoke (default: 123)
  --issue-repo <owner/repo>      Mock issue repo for linked-system smoke
  --issue-title <text>           Mock issue title
  --issue-body <text>            Mock issue body
  -h, --help                     Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workers-hub-root)
      WORKERS_HUB_ROOT="${2:-}"
      shift 2
      ;;
    --cursorvers-line-root)
      CURSORVERS_LINE_ROOT="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --issue-number)
      ISSUE_NUMBER="${2:-}"
      shift 2
      ;;
    --issue-repo)
      ISSUE_REPO="${2:-}"
      shift 2
      ;;
    --issue-title)
      ISSUE_TITLE="${2:-}"
      shift 2
      ;;
    --issue-body)
      ISSUE_BODY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: missing command '${cmd}'" >&2
    exit 2
  fi
}

require_dir() {
  local dir="$1"
  local label="$2"
  if [[ ! -d "${dir}" ]]; then
    echo "Error: ${label} not found: ${dir}" >&2
    exit 2
  fi
}

require_cmd bash
require_cmd jq
require_cmd rg
require_cmd npm
require_cmd deno

require_dir "${ROOT_DIR}" "fugue root"
require_dir "${WORKERS_HUB_ROOT}" "workers hub repo"
require_dir "${CURSORVERS_LINE_ROOT}" "cursorvers line repo"

if ! [[ "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Error: --issue-number must be numeric" >&2
  exit 2
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${OUT_DIR%/}/kernel-peripherals-${timestamp}-$$"
RESULTS_JSONL="${RUN_DIR}/results.jsonl"
mkdir -p "${RUN_DIR}"

MOCK_BIN="${RUN_DIR}/mock-bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_number="${3:-0}"
  repo="cursorvers/fugue-orchestrator"
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="${2:-${repo}}"
        shift 2
        ;;
      --json)
        shift 2
        ;;
      *)
        shift 1
        ;;
    esac
  done
  jq -cn \
    --argjson number "${issue_number}" \
    --arg title "${KERNEL_SIM_ISSUE_TITLE:-Kernel peripheral smoke}" \
    --arg body "${KERNEL_SIM_ISSUE_BODY:-Simulated issue contract for Kernel peripheral verification.}" \
    --arg url "https://github.com/${repo}/issues/${issue_number}" \
    '{
      number:$number,
      title:$title,
      body:$body,
      url:$url
    }'
  exit 0
fi

echo "mock gh only supports 'issue view'" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/gh"

append_result() {
  local id="$1"
  local status="$2"
  local workdir="$3"
  local duration_ms="$4"
  local log_file="$5"
  local message="$6"
  jq -cn \
    --arg id "${id}" \
    --arg status "${status}" \
    --arg workdir "${workdir}" \
    --argjson duration_ms "${duration_ms}" \
    --arg log_file "${log_file}" \
    --arg message "${message}" \
    '{
      id:$id,
      status:$status,
      workdir:$workdir,
      duration_ms:$duration_ms,
      log_file:$log_file,
      message:$message
    }' >> "${RESULTS_JSONL}"
}

run_step() {
  local id="$1"
  local workdir="$2"
  shift 2

  local log_file="${RUN_DIR}/${id}.log"
  local start_epoch
  local end_epoch
  local duration_ms
  local rc=0

  start_epoch="$(date +%s)"
  echo "==> ${id}"
  set +e
  (
    cd "${workdir}"
    "$@"
  ) >"${log_file}" 2>&1
  rc=$?
  set -e
  end_epoch="$(date +%s)"
  duration_ms="$(( (end_epoch - start_epoch) * 1000 ))"

  if (( rc == 0 )); then
    append_result "${id}" "ok" "${workdir}" "${duration_ms}" "${log_file}" "passed"
    echo "[PASS] ${id}"
    return 0
  fi

  append_result "${id}" "error" "${workdir}" "${duration_ms}" "${log_file}" "failed (exit ${rc})"
  echo "[FAIL] ${id} (exit ${rc})" >&2
  tail -n 40 "${log_file}" >&2 || true
  return 1
}

contract_probe() {
  local failures=0

  rg -q "protected Cursorvers business systems" "${ROOT_DIR}/docs/requirements-gpt54-codex-kernel.md" || {
    echo "missing protected business systems requirement"
    failures=1
  }
  rg -q "Kernel Peripheral Adapter Contract" "${ROOT_DIR}/docs/kernel-peripheral-adapter-contract.md" || {
    echo "missing peripheral adapter contract doc"
    failures=1
  }
  rg -q "Kernel Sovereign Adapter Contract" "${ROOT_DIR}/docs/kernel-sovereign-adapter-contract.md" || {
    echo "missing sovereign adapter contract doc"
    failures=1
  }
  rg -q "Re-switch To FUGUE" "${ROOT_DIR}/docs/kernel-fugue-migration-audit.md" || {
    echo "missing Kernel FUGUE migration audit"
    failures=1
  }
  rg -q "Cursorvers Contract Map" "${ROOT_DIR}/docs/kernel-peripheral-audit.md" || {
    echo "missing Cursorvers contract map audit"
    failures=1
  }
  jq -e '.adapters | length > 0' "${ROOT_DIR}/config/integrations/peripheral-adapters.json" >/dev/null 2>&1 || {
    echo "missing peripheral adapter manifest entries"
    failures=1
  }
  jq -e '.adapters[] | select(.id == "railway-kernel-edge-intake" and .authority == "gateway" and .ingress_auth == "webhook-signature" and .accepts_signed_payload == true and .fail_closed == true and (.dedupe_strategy | length > 0))' "${ROOT_DIR}/config/integrations/peripheral-adapters.json" >/dev/null 2>&1 || {
    echo "missing Railway edge intake fail-closed contract"
    failures=1
  }
  jq -e '.adapters[] | select(.id == "tailscale-admin-ui" and .authority == "ui-boundary" and .ingress_auth == "tailscale-auth" and .ingress_surface == "private-admin-ui")' "${ROOT_DIR}/config/integrations/peripheral-adapters.json" >/dev/null 2>&1 || {
    echo "missing Tailscale admin UI private-boundary contract"
    failures=1
  }
  jq -e '.adapters[] | select(.id == "railway-happy-web-boundary" and .authority == "ui-boundary" and .ingress_auth == "session-auth" and .ingress_surface == "public-web")' "${ROOT_DIR}/config/integrations/peripheral-adapters.json" >/dev/null 2>&1 || {
    echo "missing Railway Happy web boundary contract"
    failures=1
  }
  rg -q "dedupe_key" "${ROOT_DIR}/docs/kernel-tailscale-railway-integration-design.md" || {
    echo "missing Railway dedupe contract in design doc"
    failures=1
  }
  rg -q "deferred-relay-failure" "${ROOT_DIR}/docs/kernel-tailscale-railway-integration-design.md" || {
    echo "missing Railway deferred-relay-failure outcome in design doc"
    failures=1
  }
  rg -q "tailnet membership alone is not sufficient" "${ROOT_DIR}/docs/kernel-tailscale-railway-integration-design.md" || {
    echo "missing Tailscale privileged UI allowlist rule in design doc"
    failures=1
  }
  rg -q "SUPABASE_URL" "${ROOT_DIR}/scripts/lib/mcp-rest-bridge.sh" || {
    echo "missing Supabase REST bridge contract"
    failures=1
  }
  rg -q "Lightweight Supabase REST Client" "${WORKERS_HUB_ROOT}/src/services/supabase-client.ts" || {
    echo "missing workers Supabase client"
    failures=1
  }
  rg -q "cockpit-pwa\\.vercel\\.app" "${WORKERS_HUB_ROOT}/src/index.ts" || {
    echo "missing Vercel origin allowlist"
    failures=1
  }
  rg -q "NEXT_PUBLIC_API_URL" "${WORKERS_HUB_ROOT}/cockpit-pwa/src/app/page.tsx" || {
    echo "missing cockpit API env contract"
    failures=1
  }
  rg -q "LINE_NOTIFY_ALLOW_INBOUND_WEBHOOK" "${ROOT_DIR}/scripts/local/integrations/line-notify.sh" || {
    echo "missing LINE inbound webhook guard"
    failures=1
  }
  jq -e '.adapters | length >= 3' "${ROOT_DIR}/config/orchestration/sovereign-adapters.json" >/dev/null 2>&1 || {
    echo "missing sovereign adapter manifest entries"
    failures=1
  }
  jq -e '.adapters[] | select(.id == "fugue-bridge")' "${ROOT_DIR}/config/orchestration/sovereign-adapters.json" >/dev/null 2>&1 || {
    echo "missing fugue-bridge sovereign adapter"
    failures=1
  }
  # Skip cursorvers LINE probes when adapter is marked stub-only in peripheral-adapters.json
  local line_adapter_status
  line_adapter_status="$(jq -r '.adapters[] | select(.id == "cursorvers-line-platform") | .status // "active"' "${ROOT_DIR}/config/integrations/peripheral-adapters.json" 2>/dev/null || echo "active")"
  if [[ "${line_adapter_status}" == "stub-only" ]]; then
    echo "cursorvers-line-platform marked stub-only; skipping contract probes"
  else
    rg -q "line-webhook" "${CURSORVERS_LINE_ROOT}/README.md" || {
      echo "missing Cursorvers LINE webhook repo contract"
      failures=1
    }
    [[ -f "${CURSORVERS_LINE_ROOT}/supabase/functions/discord-relay/index.ts" ]] || {
      echo "missing Cursorvers Discord relay contract"
      failures=1
    }
  fi

  return "${failures}"
}

run_contract_probe() {
  local id="kernel_contract_probe"
  local log_file="${RUN_DIR}/${id}.log"
  local start_epoch
  local end_epoch
  local duration_ms
  local rc=0

  start_epoch="$(date +%s)"
  echo "==> ${id}"
  set +e
  contract_probe >"${log_file}" 2>&1
  rc=$?
  set -e
  end_epoch="$(date +%s)"
  duration_ms="$(( (end_epoch - start_epoch) * 1000 ))"

  if (( rc == 0 )); then
    append_result "${id}" "ok" "${ROOT_DIR}" "${duration_ms}" "${log_file}" "passed"
    echo "[PASS] ${id}"
    return 0
  fi

  append_result "${id}" "error" "${ROOT_DIR}" "${duration_ms}" "${log_file}" "failed (exit ${rc})"
  echo "[FAIL] ${id} (exit ${rc})" >&2
  cat "${log_file}" >&2 || true
  return 1
}

failures=0

run_step \
  "linked_integrity" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/scripts/check-linked-systems-integrity.sh" || failures=$((failures + 1))

run_step \
  "peripheral_adapter_contract" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/scripts/check-peripheral-adapters.sh" || failures=$((failures + 1))

run_step \
  "mcp_adapter_contract" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/scripts/check-mcp-adapters.sh" || failures=$((failures + 1))

run_step \
  "mcp_adapter_exec" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/tests/test-mcp-adapter-exec.sh" || failures=$((failures + 1))

run_step \
  "claude_teams_policy" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/tests/test-claude-teams-policy.sh" || failures=$((failures + 1))

run_step \
  "sovereign_adapter_contract" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/scripts/check-sovereign-adapters.sh" || failures=$((failures + 1))

run_step \
  "sovereign_adapter_switch_sim" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/scripts/sim-sovereign-adapter-switch.sh" || failures=$((failures + 1))

run_step \
  "fugue_bridge_runtime" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/tests/test-fugue-bridge-handoff.sh" || failures=$((failures + 1))

run_step \
  "kernel_canary_plan" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/tests/test-kernel-canary-plan.sh" || failures=$((failures + 1))

run_step \
  "orchestrator_matrix" \
  "${ROOT_DIR}" \
  bash "${ROOT_DIR}/scripts/sim-orchestrator-switch.sh" || failures=$((failures + 1))

run_step \
  "linked_systems_smoke" \
  "${ROOT_DIR}" \
  env \
  "PATH=${MOCK_BIN}:${PATH}" \
  "KERNEL_SIM_ISSUE_TITLE=${ISSUE_TITLE}" \
  "KERNEL_SIM_ISSUE_BODY=${ISSUE_BODY}" \
  "POST_ISSUE_COMMENT=false" \
  bash "${ROOT_DIR}/scripts/local/run-linked-systems.sh" \
  --issue "${ISSUE_NUMBER}" \
  --repo "${ISSUE_REPO}" \
  --mode smoke \
  --out-dir "${RUN_DIR}/linked-smoke" \
  --max-parallel 3 || failures=$((failures + 1))

run_step \
  "workers_local_agent" \
  "${WORKERS_HUB_ROOT}/local-agent" \
  bash -lc "npm run type-check && npm test -- --run src/task-executor.test.ts" || failures=$((failures + 1))

run_step \
  "workers_cockpit_pwa" \
  "${WORKERS_HUB_ROOT}/cockpit-pwa" \
  bash -lc "if [[ ! -d node_modules ]]; then npm install --ignore-scripts --no-audit --no-fund; fi && npm run lint && npm run build" || failures=$((failures + 1))

run_step \
  "workers_discord_regressions" \
  "${WORKERS_HUB_ROOT}" \
  npm test -- --run \
  src/services/reflection-notifier.test.ts \
  src/handlers/discord.test.ts \
  src/durable-objects/system-events.test.ts \
  src/services/notification-service.test.ts \
  src/services/notification-hub.test.ts \
  src/services/pwa-notifier.test.ts \
  src/fugue/cockpit-gateway.test.ts || failures=$((failures + 1))

run_step \
  "cursorvers_functions" \
  "${CURSORVERS_LINE_ROOT}" \
  deno task test:functions || failures=$((failures + 1))

run_contract_probe || failures=$((failures + 1))

results_json="${RUN_DIR}/results.json"
summary_md="${RUN_DIR}/summary.md"

jq -s '.' "${RESULTS_JSONL}" > "${results_json}"

ok_count="$(jq '[.[] | select(.status == "ok")] | length' "${results_json}")"
error_count="$(jq '[.[] | select(.status == "error")] | length' "${results_json}")"
overall_status="ok"
if (( failures > 0 || error_count > 0 )); then
  overall_status="error"
fi

{
  echo "# Kernel Peripheral Verification"
  echo
  echo "- status: ${overall_status}"
  echo "- checks: $(( ok_count + error_count ))"
  echo "- passed: ${ok_count}"
  echo "- failed: ${error_count}"
  echo "- run dir: ${RUN_DIR}"
  echo
  echo "## Checks"
  jq -r '.[] | "- \(.id): \(.status) (\(.message))"' "${results_json}"
} > "${summary_md}"

echo
echo "Kernel peripheral verification summary: ${summary_md}"
echo "Kernel peripheral verification json: ${results_json}"

if [[ "${overall_status}" != "ok" ]]; then
  exit 1
fi
