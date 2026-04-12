#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/config/orchestration/sovereign-adapters.json"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Error: sovereign adapter manifest not found: ${MANIFEST}" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: missing command 'jq'" >&2
  exit 2
fi

if ! jq -e '.adapters | type == "array"' "${MANIFEST}" >/dev/null; then
  echo "Error: manifest .adapters must be an array" >&2
  exit 2
fi

if [[ "$(jq '[.adapters[] | select(.default == true)] | length' "${MANIFEST}")" != "1" ]]; then
  echo "Error: exactly one default sovereign adapter is required" >&2
  exit 2
fi

default_id="$(jq -r '.adapters[] | select(.default == true) | .id' "${MANIFEST}")"
if [[ "${default_id}" != "codex-sovereign" ]]; then
  echo "Error: default sovereign adapter must be codex-sovereign" >&2
  exit 2
fi

required_ids=(codex-sovereign claude-sovereign-compat fugue-bridge)

for id in "${required_ids[@]}"; do
  if ! jq -e --arg id "${id}" '.adapters[] | select(.id == $id)' "${MANIFEST}" >/dev/null; then
    echo "Error: missing required adapter '${id}'" >&2
    exit 2
  fi
done

packet_keys_codex="$(jq -r '.adapters[] | select(.id == "codex-sovereign") | .required_packets[]' "${MANIFEST}" | sort)"
packet_keys_claude="$(jq -r '.adapters[] | select(.id == "claude-sovereign-compat") | .required_packets[]' "${MANIFEST}" | sort)"
packet_keys_fugue="$(jq -r '.adapters[] | select(.id == "fugue-bridge") | .required_packets[]' "${MANIFEST}" | sort)"

if [[ "${packet_keys_codex}" != "${packet_keys_claude}" ]]; then
  echo "Error: required_packets mismatch between codex-sovereign and claude-sovereign-compat" >&2
  exit 1
fi

if [[ "${packet_keys_codex}" != "${packet_keys_fugue}" ]]; then
  echo "Error: required_packets mismatch between codex-sovereign and fugue-bridge" >&2
  exit 1
fi

inv_codex="$(jq -c '.adapters[] | select(.id == "codex-sovereign") | .governance_invariants' "${MANIFEST}")"
inv_claude="$(jq -c '.adapters[] | select(.id == "claude-sovereign-compat") | .governance_invariants' "${MANIFEST}")"
inv_fugue="$(jq -c '.adapters[] | select(.id == "fugue-bridge") | .governance_invariants' "${MANIFEST}")"

if [[ "${inv_codex}" != "${inv_claude}" ]]; then
  echo "Error: governance_invariants mismatch between sovereign adapters" >&2
  exit 1
fi

if [[ "${inv_codex}" != "${inv_fugue}" ]]; then
  echo "Error: governance_invariants mismatch between codex-sovereign and fugue-bridge" >&2
  exit 1
fi

if ! jq -e '.adapters[] | select(.id == "claude-sovereign-compat") | .adapter_boundary.encapsulates_provider_limits == true and .adapter_boundary.encapsulates_agent_teams_policy == true and .adapter_boundary.core_provider_branching_forbidden == true' "${MANIFEST}" >/dev/null; then
  echo "Error: claude-sovereign-compat boundary guarantees are incomplete" >&2
  exit 1
fi

if ! jq -e '.adapters[] | select(.id == "fugue-bridge") | .provider == "legacy-fugue" and .class == "legacy-bridge" and .availability == "rollback-ready"' "${MANIFEST}" >/dev/null; then
  echo "Error: fugue-bridge rollback guarantees are incomplete" >&2
  exit 1
fi

printf "scenario\tadapter\tprovider\tclass\tavailability\tprotocol_version\tpacket_schema\tpacket_count\tinvariants_hash\n"
for id in "${required_ids[@]}"; do
  jq -r --arg id "${id}" '
    .adapters[]
    | select(.id == $id)
    | [
        "SOV-" + ($id | ascii_upcase),
        .id,
        .provider,
        .class,
        .availability,
        .protocol_version,
        .packet_schema,
        (.required_packets | length | tostring),
        (.governance_invariants | tostring)
      ]
    | @tsv
  ' "${MANIFEST}"
done
