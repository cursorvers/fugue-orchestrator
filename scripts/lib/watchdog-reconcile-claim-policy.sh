#!/usr/bin/env bash
set -euo pipefail

pending_json='[]'
previous_state_json='{}'
persist_state='false'
now_epoch="$(date +%s)"
ttl_seconds='1800'
format='json'

usage() {
  cat <<'EOF'
Usage:
  scripts/lib/watchdog-reconcile-claim-policy.sh [options]

Options:
  --pending-json <json>
  --previous-state-json <json>
  --persist-state <true|false>
  --now-epoch <unix-seconds>
  --ttl-seconds <seconds>
  --format <json|env>
  -h, --help
EOF
}

to_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" || "${value}" == "1" || "${value}" == "yes" || "${value}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

normalize_int() {
  local value="${1:-}"
  local fallback="${2:-0}"
  if [[ "${value}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${fallback}"
  fi
}

normalize_pending_json() {
  local raw="${1:-[]}"
  local normalized
  normalized="$(
    printf '%s\n' "${raw}" | jq -cs '
      (map(select(type == "array")) | first // [])
      | map(select(type == "number" or type == "string"))
    ' 2>/dev/null
  )" || normalized='[]'
  if [[ -z "${normalized}" ]]; then
    normalized='[]'
  fi
  printf '%s' "${normalized}"
}

normalize_claim_state_json() {
  local raw="${1:-}"
  local normalized
  if [[ -z "${raw}" ]]; then
    raw='{}'
  fi
  normalized="$(
    printf '%s\n' "${raw}" | jq -cs '
      (map(select(type == "object")) | first // {})
      | .claims = (
          (.claims // {})
          | if type == "object" then . else {} end
        )
    ' 2>/dev/null
  )" || normalized='{"claims":{}}'
  if [[ -z "${normalized}" ]]; then
    normalized='{"claims":{}}'
  fi
  printf '%s' "${normalized}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pending-json) pending_json="${2:-"[]"}"; shift 2 ;;
    --previous-state-json) previous_state_json="${2:-"{}"}"; shift 2 ;;
    --persist-state) persist_state="${2:-false}"; shift 2 ;;
    --now-epoch) now_epoch="${2:-}"; shift 2 ;;
    --ttl-seconds) ttl_seconds="${2:-}"; shift 2 ;;
    --format) format="${2:-json}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

persist_state="$(to_bool "${persist_state}")"
now_epoch="$(normalize_int "${now_epoch}" "$(date +%s)")"
ttl_seconds="$(normalize_int "${ttl_seconds}" "1800")"
if (( ttl_seconds <= 0 )); then
  ttl_seconds=1800
fi
if [[ "${format}" != "json" && "${format}" != "env" ]]; then
  echo "Error: --format must be json|env" >&2
  exit 2
fi
pending_json="$(normalize_pending_json "${pending_json}")"
previous_state_json="$(normalize_claim_state_json "${previous_state_json}")"

policy_json="$(
  jq -cn \
    --argjson pending "${pending_json}" \
    --argjson previous "${previous_state_json}" \
    --argjson now "${now_epoch}" \
    --argjson ttl "${ttl_seconds}" \
    --arg persist "${persist_state}" '
      def unique_pending:
        ($pending | map(tonumber) | unique);
      def prev_claims:
        ($previous.claims // {});
      def is_active($claim):
        (($claim.expires_at // 0) | tonumber) > $now;
      def keep_claim($issue):
        (prev_claims[($issue | tostring)] // null) as $claim
        | ($claim != null and is_active($claim));
      def next_claim($issue):
        {
          issue_number: $issue,
          claimed_at: $now,
          expires_at: ($now + $ttl),
          source: "watchdog-reconcile",
          status: "claimed"
        };

      (unique_pending) as $pending_unique
      | ($pending_unique | map(select(keep_claim(.)))) as $retained_numbers
      | ($pending_unique | map(select((keep_claim(.)) | not))) as $dispatch_numbers
      | ($retained_numbers | map({
          key: (. | tostring),
          value: (prev_claims[(. | tostring)] + {issue_number: ., status: "claimed"})
        }) | from_entries) as $retained_claims
      | ($dispatch_numbers | map({
          key: (. | tostring),
          value: next_claim(.)
        }) | from_entries) as $new_claims
      | ($retained_claims + $new_claims) as $next_claims
      | {
          dispatch_issue_numbers: $dispatch_numbers,
          dispatch_count: ($dispatch_numbers | length),
          retained_issue_numbers: $retained_numbers,
          state_update_required: (
            (($previous.claims // {}) != $next_claims)
          ),
          persist_state: ($persist == "true"),
          next_state: {
            claims: $next_claims
          }
        }
    '
)"

if [[ "${format}" == "env" ]]; then
  dispatch_json="$(printf '%s' "${policy_json}" | jq -c '.dispatch_issue_numbers')"
  dispatch_count="$(printf '%s' "${policy_json}" | jq -r '.dispatch_count')"
  retained_json="$(printf '%s' "${policy_json}" | jq -c '.retained_issue_numbers')"
  state_update_required="$(printf '%s' "${policy_json}" | jq -r '.state_update_required')"
  next_state_json="$(printf '%s' "${policy_json}" | jq -c '.next_state')"
  persist_state_effective="$(printf '%s' "${policy_json}" | jq -r '.persist_state')"
  {
    printf 'dispatch_issue_numbers_json=%q\n' "${dispatch_json}"
    echo "dispatch_count=${dispatch_count}"
    printf 'retained_issue_numbers_json=%q\n' "${retained_json}"
    echo "state_update_required=${state_update_required}"
    echo "persist_state=${persist_state_effective}"
    printf 'next_state_json=%q\n' "${next_state_json}"
  }
  exit 0
fi

printf '%s\n' "${policy_json}"
