#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/config/orchestration/sovereign-adapters.json"
CONTRACT_DOC="${ROOT_DIR}/docs/kernel-sovereign-adapter-contract.md"
REQUIREMENTS_DOC="${ROOT_DIR}/docs/requirements-gpt54-codex-kernel.md"
AUDIT_DOC="${ROOT_DIR}/docs/kernel-fugue-migration-audit.md"

EXPECTED_PACKETS='["artifact_packet","classification","council_packet","decision_packet","fallback_packet","intake","topology_request"]'
REQUIRED_ADAPTERS='["codex-sovereign","claude-sovereign-compat","fugue-bridge"]'

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

require_cmd jq
require_cmd rg
[[ -f "${MANIFEST}" ]] || fail "manifest not found: ${MANIFEST}"
[[ -f "${CONTRACT_DOC}" ]] || fail "contract doc not found: ${CONTRACT_DOC}"
[[ -f "${REQUIREMENTS_DOC}" ]] || fail "requirements doc not found: ${REQUIREMENTS_DOC}"
[[ -f "${AUDIT_DOC}" ]] || fail "audit doc not found: ${AUDIT_DOC}"

jq -e '.adapters | type == "array"' "${MANIFEST}" >/dev/null || fail "manifest .adapters must be an array"
adapter_count="$(jq '.adapters | length' "${MANIFEST}")"
(( adapter_count >= 3 )) || fail "manifest must have at least 3 adapters"
pass "adapter count: ${adapter_count}"

dups="$(jq -r '.adapters | group_by(.id)[] | select(length > 1) | .[0].id' "${MANIFEST}")"
[[ -z "${dups}" ]] || fail "duplicate adapter IDs: ${dups}"
pass "adapter IDs are unique"

missing_required="$(jq -r --argjson required "${REQUIRED_ADAPTERS}" '
  ($required - [.adapters[].id])[]?
' "${MANIFEST}")"
[[ -z "${missing_required}" ]] || fail "missing required adapters: ${missing_required}"
pass "required adapters present"

default_count="$(jq '[.adapters[] | select(.default == true)] | length' "${MANIFEST}")"
[[ "${default_count}" == "1" ]] || fail "exactly one default sovereign adapter is required"
default_id="$(jq -r '.adapters[] | select(.default == true) | .id' "${MANIFEST}")"
[[ "${default_id}" == "codex-sovereign" ]] || fail "default sovereign adapter must be codex-sovereign"
pass "default sovereign adapter valid"

enum_failures="$(jq -r '
  .adapters[]
  | select(
      (.provider | IN("codex","claude","legacy-fugue") | not)
      or (.class | IN("sovereign","sovereign-compat","legacy-bridge") | not)
      or (.availability | IN("active","compat-ready","rollback-ready","disabled") | not)
      or (.protocol_version != "kernel.v1")
      or (.packet_schema != "kernel.protocol.v1.packets")
      or (.adapter_boundary.encapsulates_provider_limits | type != "boolean")
      or (.adapter_boundary.encapsulates_agent_teams_policy | type != "boolean")
      or (.adapter_boundary.core_provider_branching_forbidden | type != "boolean")
    )
  | .id
' "${MANIFEST}")"
[[ -z "${enum_failures}" ]] || fail "adapter entries with invalid enum/schema values: ${enum_failures}"
pass "adapter enums and schema markers valid"

packet_failures="$(jq -r --argjson expected "${EXPECTED_PACKETS}" '
  .adapters[]
  | select(((.required_packets | sort) != $expected))
  | .id
' "${MANIFEST}")"
[[ -z "${packet_failures}" ]] || fail "adapter packet contract mismatch: ${packet_failures}"
pass "required packet set parity valid"

invariant_failures="$(jq -r '
  .adapters[]
  | select(
      (.governance_invariants.weighted_two_thirds_consensus != true)
      or (.governance_invariants.high_risk_veto != true)
      or (.governance_invariants.baseline_council_required_for_non_trivial_writes != true)
      or (.governance_invariants.human_approval_gate_for_destructive_or_irreversible_actions != true)
      or (.governance_invariants.run_trace_schema_stable != true)
      or (.governance_invariants.linked_system_dispatch_contract_stable != true)
    )
  | .id
' "${MANIFEST}")"
[[ -z "${invariant_failures}" ]] || fail "adapter governance invariant mismatch: ${invariant_failures}"
pass "governance invariants valid"

claude_boundary_failures="$(jq -r '
  .adapters[]
  | select(.id == "claude-sovereign-compat")
  | select(
      (.adapter_boundary.encapsulates_provider_limits != true)
      or (.adapter_boundary.encapsulates_agent_teams_policy != true)
      or (.adapter_boundary.core_provider_branching_forbidden != true)
    )
  | .id
' "${MANIFEST}")"
[[ -z "${claude_boundary_failures}" ]] || fail "claude sovereign boundary contract invalid"
pass "claude sovereign boundary contract valid"

fugue_bridge_failures="$(jq -r '
  .adapters[]
  | select(.id == "fugue-bridge")
  | select(
      (.provider != "legacy-fugue")
      or (.class != "legacy-bridge")
      or (.availability != "rollback-ready")
      or (.adapter_boundary.encapsulates_provider_limits != true)
      or (.adapter_boundary.encapsulates_agent_teams_policy != true)
      or (.adapter_boundary.core_provider_branching_forbidden != true)
    )
  | .id
' "${MANIFEST}")"
[[ -z "${fugue_bridge_failures}" ]] || fail "fugue bridge rollback contract invalid"
pass "fugue bridge rollback contract valid"

rg -q "fugue-bridge" "${CONTRACT_DOC}" || fail "sovereign adapter contract doc must mention fugue-bridge"
rg -q "fugue-bridge" "${REQUIREMENTS_DOC}" || fail "requirements doc must mention fugue-bridge"
rg -q "Re-switch To FUGUE" "${AUDIT_DOC}" || fail "migration audit must cover FUGUE re-switch"
pass "sovereign adapter docs and migration audit aligned"

echo "sovereign adapter contract check passed"
