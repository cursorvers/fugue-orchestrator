#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
HEALTH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
STATUS_SURFACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-status-surface.sh"

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

usage() {
  cat <<'EOF'
Usage:
  kernel-4pane-surface.sh snapshot-path [run_id]
  kernel-4pane-surface.sh active-file
  kernel-4pane-surface.sh snapshot [--write] [run_id]
  kernel-4pane-surface.sh render-lanes [run_id]
  kernel-4pane-surface.sh render-health [run_id]
  kernel-4pane-surface.sh render-ship [run_id]
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

workspace_receipt_path() {
  local run_id="${1:-${RUN_ID}}"
  KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" receipt-path 2>/dev/null || true
}

workspace_receipt_json() {
  local run_id="${1:-${RUN_ID}}"
  local path
  path="$(workspace_receipt_path "${run_id}")"
  [[ -n "${path}" && -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

artifacts_dir_for() {
  local run_id="${1:-${RUN_ID}}"
  local json path
  if json="$(workspace_receipt_json "${run_id}" 2>/dev/null)"; then
    path="$(jq -r '.artifacts_dir // empty' <<<"${json}")"
    if [[ -n "${path}" ]]; then
      mkdir -p "${path}"
      printf '%s\n' "${path}"
      return 0
    fi
  fi
  path="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" ensure)"
  mkdir -p "${path}/artifacts"
  printf '%s/artifacts\n' "${path}"
}

snapshot_path_for() {
  local run_id="${1:-${RUN_ID}}"
  printf '%s/4pane-state.json\n' "$(artifacts_dir_for "${run_id}")"
}

active_file() {
  bash "${STATE_PATH_SCRIPT}" 4pane-active-file
}

receipt_path_for() {
  local run_id="${1:-${RUN_ID}}"
  KERNEL_RUN_ID="${run_id}" bash "${RECEIPT_SCRIPT}" path 2>/dev/null || true
}

compact_path_for() {
  local run_id="${1:-${RUN_ID}}"
  KERNEL_RUN_ID="${run_id}" bash "${COMPACT_SCRIPT}" path 2>/dev/null || true
}

ledger_file() {
  printf '%s\n' "${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
}

shape_from_health_state() {
  case "${1:-invalid}" in
    healthy) printf 'NORMAL\n' ;;
    degraded-allowed) printf 'DEGRADED\n' ;;
    *) printf 'BLOCKED\n' ;;
  esac
}

normalize_health_json() {
  local run_id="${1:-${RUN_ID}}"
  local out rc
  set +e
  out="$(KERNEL_RUN_ID="${run_id}" KERNEL_RUNTIME_HEALTH_MUTATE=false bash "${HEALTH_SCRIPT}" status 2>&1)"
  rc=$?
  set -e
  HEALTH_TEXT="${out}" python3 - "${rc}" <<'PY'
import json, re, sys

rc = int(sys.argv[1])
import os
text = os.environ.get("HEALTH_TEXT", "")
data = {"exit_code": rc, "raw": text.strip()}
for line in text.splitlines():
    m = re.match(r"\s*-\s*([^:]+):\s*(.*)", line)
    if not m:
        continue
    key = m.group(1).strip().lower().replace(" ", "_")
    data[key] = m.group(2).strip()
print(json.dumps(data))
PY
}

status_surface_json() {
  if [[ -f "${STATUS_SURFACE_SCRIPT}" ]]; then
    bash "${STATUS_SURFACE_SCRIPT}" snapshot 2>/dev/null || printf '{"summary":{}}\n'
  else
    printf '{"summary":{}}\n'
  fi
}

render_table() {
  python3 -c '
import json, sys
rows = json.load(sys.stdin)
if not rows:
    sys.exit(0)
widths = []
for row in rows:
    for i, cell in enumerate(row):
        if len(widths) <= i:
            widths.append(0)
        widths[i] = max(widths[i], len(cell))
for row in rows:
    print("  " + " | ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))
'
}

provider_rows_json() {
  local run_id="${1:?run_id is required}"
  local snapshot_json="${2:?snapshot_json is required}"
  local ledger_path usage_json
  ledger_path="$(ledger_file)"
  if [[ -f "${ledger_path}" ]]; then
    usage_json="$(jq -c --arg run_id "${run_id}" '.runs[$run_id].provider_usage // {}' "${ledger_path}")"
  else
    usage_json='{}'
  fi

  jq -n \
    --argjson snapshot "${snapshot_json}" \
    --argjson usage "${usage_json}" \
    '
      ($snapshot.receipt.providers // []) as $providers
      | ($snapshot.receipt.active_models // []) as $models
      | [
          ["provider", "model", "role", "evidence"],
          (
            $providers
            | to_entries[]
            | [
                .value,
                ($models[.key] // "-"),
                (
                  if .value == "codex" then "sovereign"
                  elif .value == "glm" then "critic"
                  else "specialist"
                  end
                ),
                (
                  ($usage[.value].success_count // 0 | tonumber) as $success
                  | ($usage[.value].failure_count // 0 | tonumber) as $failure
                  | if $success > 0 and $failure > 0 then "ok/" + ($failure | tostring) + " fail"
                    elif $success > 0 then "ok"
                    elif $failure > 0 then ($failure | tostring) + " fail"
                    else "pending"
                    end
                )
              ]
          )
        ]
    '
}

cmd_snapshot_path() {
  printf '%s\n' "$(snapshot_path_for "${1:-${RUN_ID}}")"
}

cmd_snapshot() {
  local write_snapshot=false
  local run_id="${RUN_ID}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --write)
        write_snapshot=true
        shift
        ;;
      *)
        run_id="$1"
        shift
        ;;
    esac
  done

  local receipt_path compact_path ledger_path health_json compact_json receipt_json status_json shape
  receipt_path="$(receipt_path_for "${run_id}")"
  compact_path="$(compact_path_for "${run_id}")"
  ledger_path="$(ledger_file)"
  health_json="$(normalize_health_json "${run_id}")"
  shape="$(shape_from_health_state "$(jq -r '.state // "invalid"' <<<"${health_json}")")"

  if [[ -f "${compact_path}" ]]; then
    compact_json="$(jq -c '.' "${compact_path}")"
  else
    compact_json='{}'
  fi
  if [[ -f "${receipt_path}" ]]; then
    receipt_json="$(jq -c '.' "${receipt_path}")"
  else
    receipt_json='{}'
  fi
  status_json="$(status_surface_json)"

  local snapshot_json
  snapshot_json="$(
    jq -n \
      --arg version "1" \
      --arg generated_at "$(utc_timestamp)" \
      --arg run_id "${run_id}" \
      --arg snapshot_path "$(snapshot_path_for "${run_id}")" \
      --arg receipt_path "${receipt_path}" \
      --arg compact_path "${compact_path}" \
      --arg ledger_path "${ledger_path}" \
      --arg shape "${shape}" \
      --argjson health "${health_json}" \
      --argjson receipt "${receipt_json}" \
      --argjson compact "${compact_json}" \
      --argjson status_surface "${status_json}" \
      '{
        version: ($version | tonumber),
        generated_at: $generated_at,
        run_id: $run_id,
        source_of_truth: {
          bootstrap_receipt_path: $receipt_path,
          compact_artifact_path: $compact_path,
          runtime_ledger_path: $ledger_path
        },
        projection_path: $snapshot_path,
        shape: $shape,
        health: $health,
        receipt: {
          lane_count: ($receipt.lane_count // 0),
          mode: ($receipt.mode // "unknown"),
          providers: ($receipt.providers // []),
          active_models: ($receipt.active_models // []),
          manifest_lane_count: ($receipt.manifest_lane_count // 0),
          has_agent_labels: ($receipt.has_agent_labels // false),
          has_subagent_labels: ($receipt.has_subagent_labels // false)
        },
        compact: {
          project: ($compact.project // ""),
          purpose: ($compact.purpose // ""),
          runtime: ($compact.runtime // ""),
          current_phase: ($compact.current_phase // ""),
          mode: ($compact.mode // ""),
          next_action: ($compact.next_action // []),
          summary: ($compact.summary // []),
          active_models: ($compact.active_models // []),
          tmux_session: ($compact.tmux_session // ""),
          updated_at: ($compact.updated_at // "")
        },
        status_surface: {
          active_claims: ($status_surface.summary.active_claims // 0),
          running: ($status_surface.summary.running // 0),
          retrying: ($status_surface.summary.retrying // 0),
          degraded: ($status_surface.summary.degraded // 0),
          blocked: ($status_surface.summary.blocked // 0),
          terminal: ($status_surface.summary.terminal // 0),
          preferred_recovery: ($status_surface.recovery_handoff.preferred_recovery // "idle")
        }
      }'
  )"

  if [[ "${write_snapshot}" == "true" ]]; then
    local path tmp_file
    path="$(snapshot_path_for "${run_id}")"
    mkdir -p "$(dirname "${path}")"
    tmp_file="$(umask 077 && mktemp "${path}.tmp.XXXXXXXXXX")"
    printf '%s\n' "${snapshot_json}" >"${tmp_file}"
    mv "${tmp_file}" "${path}"
  fi

  printf '%s\n' "${snapshot_json}"
}

cmd_render_lanes() {
  local run_id="${1:-${RUN_ID}}"
  local snapshot_json
  snapshot_json="$(cmd_snapshot "${run_id}")"
  printf 'Kernel 4-pane lanes\n'
  printf 'run: %s\n' "${run_id}"
  printf 'shape: %s\n' "$(jq -r '.shape' <<<"${snapshot_json}")"
  printf 'mode: %s\n' "$(jq -r '.receipt.mode' <<<"${snapshot_json}")"
  printf 'active models: %s\n' "$(jq -r '(.receipt.active_models | join(", ")) // ""' <<<"${snapshot_json}")"
  printf 'providers: %s\n' "$(jq -r '(.receipt.providers | join(", ")) // ""' <<<"${snapshot_json}")"
  printf 'manifest lanes: %s\n' "$(jq -r '.receipt.manifest_lane_count' <<<"${snapshot_json}")"
  printf 'agent labels: %s | subagent labels: %s\n' \
    "$(jq -r '.receipt.has_agent_labels' <<<"${snapshot_json}")" \
    "$(jq -r '.receipt.has_subagent_labels' <<<"${snapshot_json}")"
  printf '\n'
  provider_rows_json "${run_id}" "${snapshot_json}" | render_table
  printf '\n'
  printf '  projection source: bootstrap receipt + runtime ledger.\n'
  printf '  evidence reflects recorded provider success/failure counts, not live process tracing.\n'
}

cmd_render_health() {
  local run_id="${1:-${RUN_ID}}"
  local snapshot_json
  snapshot_json="$(cmd_snapshot "${run_id}")"
  printf 'Kernel 4-pane health\n'
  printf 'run: %s\n' "${run_id}"
  printf 'shape: %s\n' "$(jq -r '.shape' <<<"${snapshot_json}")"
  printf 'state: %s\n' "$(jq -r '.health.state // "unknown"' <<<"${snapshot_json}")"
  printf 'reason: %s\n' "$(jq -r '.health.reason // ""' <<<"${snapshot_json}")"
  printf 'lifecycle: %s\n' "$(jq -r '.health.lifecycle_state // "unknown"' <<<"${snapshot_json}")"
  printf 'scheduler: %s\n' "$(jq -r '.health.scheduler_state // "unknown"' <<<"${snapshot_json}")"
  printf 'phase: %s\n' "$(jq -r '.compact.current_phase // "unknown"' <<<"${snapshot_json}")"
  printf 'runtime: %s\n' "$(jq -r '.compact.runtime // "kernel"' <<<"${snapshot_json}")"
  printf 'next: %s\n' "$(jq -r '(.compact.next_action[0] // "continue")' <<<"${snapshot_json}")"
  printf 'claims: active=%s running=%s degraded=%s blocked=%s terminal=%s\n' \
    "$(jq -r '.status_surface.active_claims' <<<"${snapshot_json}")" \
    "$(jq -r '.status_surface.running' <<<"${snapshot_json}")" \
    "$(jq -r '.status_surface.degraded' <<<"${snapshot_json}")" \
    "$(jq -r '.status_surface.blocked' <<<"${snapshot_json}")" \
    "$(jq -r '.status_surface.terminal' <<<"${snapshot_json}")"
  case "$(jq -r '.shape' <<<"${snapshot_json}")" in
    NORMAL) printf '\nstatus: NORMAL\n' ;;
    DEGRADED) printf '\nstatus: DEGRADED\n' ;;
    *) printf '\nstatus: BLOCKED\n' ;;
  esac
}

cmd_render_ship() {
  local run_id="${1:-${RUN_ID}}"
  local compact_path branch dirty_count
  compact_path="$(compact_path_for "${run_id}")"
  branch="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  dirty_count="$(git -C "${ROOT_DIR}" status --short 2>/dev/null | wc -l | tr -d ' ')"
  printf 'Kernel 4-pane ship\n'
  printf 'run: %s\n' "${run_id}"
  printf 'branch: %s\n' "${branch}"
  printf 'dirty files: %s\n' "${dirty_count}"
  printf 'ship enabled: %s\n' "${KERNEL_4PANE_SHIP_ENABLED:-false}"
  printf 'dry run: %s\n' "${KERNEL_4PANE_SHIP_DRY_RUN:-true}"
  if [[ "${branch}" == "main" || "${branch}" == "master" ]]; then
    printf 'status: BLOCKED (protected branch)\n'
  elif [[ "${dirty_count}" == "0" ]]; then
    printf 'status: IDLE (no local changes)\n'
  elif [[ "${KERNEL_4PANE_SHIP_ENABLED:-false}" != "true" ]]; then
    printf 'status: STAGED (monitor only)\n'
  elif [[ "${KERNEL_4PANE_SHIP_DRY_RUN:-true}" == "true" ]]; then
    printf 'status: READY (dry-run)\n'
  else
    printf 'status: READY\n'
  fi
  if [[ -f "${compact_path}" ]]; then
    printf 'phase: %s\n' "$(jq -r '.current_phase // "unknown"' "${compact_path}")"
    printf 'next: %s\n' "$(jq -r '(.next_action[0] // "continue")' "${compact_path}")"
  fi
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  snapshot-path)
    cmd_snapshot_path "$@"
    ;;
  active-file)
    active_file
    ;;
  snapshot)
    cmd_snapshot "$@"
    ;;
  render-lanes)
    cmd_render_lanes "$@"
    ;;
  render-health)
    cmd_render_health "$@"
    ;;
  render-ship)
    cmd_render_ship "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
