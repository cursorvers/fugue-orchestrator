#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
COMPACT_DIR="${KERNEL_COMPACT_DIR:-$(bash "${STATE_PATH_SCRIPT}" compact-dir)}"

usage() {
  cat <<'EOF'
Usage:
  kernel-memory-query.sh search [--limit N] [--run <run_id>] [--format <text|json>] <query>
EOF
}

compact_files() {
  [[ -d "${COMPACT_DIR}" ]] || return 0
  find "${COMPACT_DIR}" -maxdepth 1 -type f -name '*.json' | sort
}

valid_docs_json() {
  local run_filter="${1:-}"
  local json path run_id
  local docs=""

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    json="$(jq -c '.' "${path}" 2>/dev/null || true)"
    [[ -n "${json}" ]] || continue
    jq -e 'type == "object"' <<<"${json}" >/dev/null 2>&1 || continue
    if [[ -n "${run_filter}" ]]; then
      run_id="$(jq -r '.run_id // ""' <<<"${json}" 2>/dev/null || true)"
      [[ "${run_id}" == "${run_filter}" ]] || continue
    fi
    json="$(jq -cn --arg path "${path}" --argjson doc "${json}" '$doc + {compact_path: $path}')"
    if [[ -z "${docs}" ]]; then
      docs="${json}"
    else
      docs="${docs}"$'\n'"${json}"
    fi
  done < <(compact_files)

  if [[ -z "${docs}" ]]; then
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "${docs}" | jq -cs '.'
}

normalize_query() {
  local value="${1:-}"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "${value}" | sed -E 's/[^a-z0-9]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]{2,}/ /g')"
  printf '%s\n' "${value}"
}

cmd_search_json() {
  local query="${1:?query is required}"
  local limit="${2:-5}"
  local run_filter="${3:-}"
  local normalized_query
  local normalized_tokens
  local docs_json

  normalized_query="$(normalize_query "${query}")"
  normalized_tokens="$(printf '%s\n' "${normalized_query}" | awk '{count=0; for (i=1; i<=NF; i++) if (length($i) > 1) count++; print count}')"
  [[ -n "${normalized_query}" && "${normalized_tokens}" -gt 0 ]] || {
    echo "query must contain at least one alphanumeric token with 2 or more characters" >&2
    exit 2
  }

  docs_json="$(valid_docs_json "${run_filter}")"
  if [[ "${docs_json}" == "[]" ]]; then
    jq -cn \
      --arg query "${normalized_query}" \
      --arg run_filter "${run_filter}" \
      '{
        query: $query,
        run_filter: (if $run_filter == "" then null else $run_filter end),
        searched_runs: 0,
        matched_runs: 0,
        results: []
      }'
    return 0
  fi

  jq -cn \
    --argjson docs "${docs_json}" \
    --arg query "${normalized_query}" \
    --arg run_filter "${run_filter}" \
    --argjson limit "${limit}" \
    '
      def norm:
        if . == null then ""
        elif (type == "string") then .
        elif (type == "array") then map(tostring) | join(" ")
        elif (type == "object") then tojson
        else tostring
        end
        | ascii_downcase
        | gsub("[^a-z0-9]+"; " ")
        | gsub("^ +| +$"; "");

      def phase_value:
        .current_phase // .phase // "";

      def matched_tokens($haystack; $tokens):
        [ $tokens[] as $token | select($haystack | contains($token)) | $token ];

      $docs as $docs
      | ($query | norm) as $normalized_query
      | ($normalized_query | split(" ") | map(select(length > 1)) | unique) as $tokens
      | [ $docs[]
          | . as $doc
          | (.summary // []) as $summary
          | (.decisions // []) as $decisions
          | (.next_action // []) as $next_action
          | ((.phase_artifacts // {}) | keys) as $phase_artifact_keys
          | (.context_reference // {}) as $context_reference
          | ([
              .run_id,
              .project,
              .purpose,
              phase_value,
              .mode,
              $summary,
              $decisions,
              $next_action,
              $phase_artifact_keys,
              .workspace_receipt_path,
              .consensus_receipt_path,
              $context_reference.path,
              $context_reference.label
            ] | map(norm) | join(" ")) as $haystack
          | (((.run_id // "") | norm) == $normalized_query
              or ((.project // "") | norm) == $normalized_query
              or ((.purpose // "") | norm) == $normalized_query) as $exact
          | (($normalized_query != "") and ($haystack | contains($normalized_query))) as $phrase
          | (matched_tokens($haystack; $tokens) | unique) as $matched_tokens
          | ($matched_tokens | length) as $token_hits
          | (if $exact then 1000 elif $phrase then 200 else 0 end) as $base_score
          | ($base_score + ($token_hits * 10)) as $score
          | select($score > 0)
          | {
              run_id: (.run_id // ""),
              project: (.project // ""),
              purpose: (.purpose // ""),
              phase: phase_value,
              mode: (.mode // ""),
              updated_at: (.updated_at // ""),
              score: $score,
              match_stage: (if $exact then "exact" elif $phrase then "phrase" else "token" end),
              matched_tokens: $matched_tokens,
              summary: $summary,
              decisions: $decisions,
              next_action: $next_action,
              phase_artifact_keys: $phase_artifact_keys,
              compact_path: (.compact_path // ""),
              workspace_receipt_path: (.workspace_receipt_path // ""),
              consensus_receipt_path: (.consensus_receipt_path // ""),
              context_reference_path: ($context_reference.path // ""),
              context_reference_label: ($context_reference.label // "")
            }
        ] as $matches
      | {
          query: $normalized_query,
          run_filter: (if $run_filter == "" then null else $run_filter end),
          searched_runs: ($docs | length),
          matched_runs: ($matches | length),
          results: ($matches | sort_by(.score, .updated_at) | reverse | .[:$limit])
        }
    '
}

cmd_search() {
  local format="${1:-text}"
  local query="${2:?query is required}"
  local limit="${3:-5}"
  local run_filter="${4:-}"
  local json

  json="$(cmd_search_json "${query}" "${limit}" "${run_filter}")"
  if [[ "${format}" == "json" ]]; then
    printf '%s\n' "${json}"
    return 0
  fi

  printf 'kernel memory query:\n'
  jq -r '
    "  - query: \(.query)",
    "  - run filter: \(.run_filter // "none")",
    "  - searched runs: \(.searched_runs)",
    "  - matched runs: \(.matched_runs)"
  ' <<<"${json}"

  if [[ "$(jq -r '.matched_runs' <<<"${json}")" == "0" ]]; then
    printf '  - results: none\n'
    return 0
  fi

  jq -r '
    .results
    | to_entries[]
    | "  - result \(.key + 1): run=\(.value.run_id) | stage=\(.value.match_stage) | score=\(.value.score) | project=\(.value.project) | purpose=\(.value.purpose) | phase=\(.value.phase) | updated_at=\(.value.updated_at) | summary=\((.value.summary // []) | join(" || "))"
  ' <<<"${json}"
}

cmd="${1:-help}"
case "${cmd}" in
  search)
    shift || true
    limit=5
    run_filter=""
    format="text"
    query=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --limit)
          limit="${2:-}"
          [[ "${limit}" =~ ^[1-9][0-9]*$ ]] || {
            echo "--limit must be a positive integer" >&2
            exit 2
          }
          shift 2
          ;;
        --run)
          run_filter="${2:-}"
          [[ -n "${run_filter}" ]] || {
            echo "--run requires a run id" >&2
            exit 2
          }
          shift 2
          ;;
        --format)
          format="${2:-}"
          case "${format}" in
            text|json) ;;
            *)
              echo "--format must be text or json" >&2
              exit 2
              ;;
          esac
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          if [[ -z "${query}" ]]; then
            query="$1"
          else
            query="${query} $1"
          fi
          shift
          ;;
      esac
    done
    [[ -n "${query}" ]] || {
      echo "search requires a query" >&2
      exit 2
    }
    cmd_search "${format}" "${query}" "${limit}" "${run_filter}"
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
