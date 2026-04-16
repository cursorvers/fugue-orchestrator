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
  kernel-memory-query.sh packet [--run <run_id> | <query>] [--format <text|json>]
EOF
}

compact_files() {
  [[ -d "${COMPACT_DIR}" ]] || return 0
  find "${COMPACT_DIR}" -maxdepth 1 -type f -name '*.json' ! -name '*.handoff.json' | sort
}

normalize_query() {
  local value="${1:-}"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "${value}" | sed -E 's/[^a-z0-9]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]{2,}/ /g')"
  printf '%s\n' "${value}"
}

valid_docs_json() {
  local run_filter="${1:-}"
  local docs=""
  local path json run_id

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    json="$(jq -c '.' "${path}" 2>/dev/null || true)"
    [[ -n "${json}" ]] || continue
    jq -e 'type == "object"' <<<"${json}" >/dev/null 2>&1 || continue
    if [[ -n "${run_filter}" ]]; then
      run_id="$(jq -r '.run_id // ""' <<<"${json}")"
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

cmd_search_json() {
  local query="${1:?query is required}"
  local limit="${2:-5}"
  local run_filter="${3:-}"
  local normalized_query normalized_tokens docs_json

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
              .handoff_packet_path,
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
              current_phase: phase_value,
              mode: (.mode // ""),
              runtime: (.runtime // ""),
              lifecycle_state: (.lifecycle_state // ""),
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
              handoff_packet_path: (.handoff_packet_path // ""),
              handoff_packet_sha256: (.handoff_packet_sha256 // ""),
              context_reference: $context_reference
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
    | "  - result \(.key + 1): run=\(.value.run_id) | stage=\(.value.match_stage) | score=\(.value.score) | project=\(.value.project) | purpose=\(.value.purpose) | phase=\(.value.current_phase) | updated_at=\(.value.updated_at) | summary=\((.value.summary // []) | join(" || "))"
  ' <<<"${json}"
}

compact_json_for_run() {
  local run_id="${1:?run id is required}"
  local docs_json
  docs_json="$(valid_docs_json "${run_id}")"
  jq -c '.[0] // {}' <<<"${docs_json}"
}

packet_json_from_doc() {
  local doc_json="${1:?doc json is required}"
  local packet_path packet_json
  packet_path="$(jq -r '.handoff_packet_path // ""' <<<"${doc_json}")"
  if [[ -n "${packet_path}" && -f "${packet_path}" ]]; then
    packet_json="$(jq -c '.' "${packet_path}" 2>/dev/null || true)"
    if [[ -n "${packet_json}" ]]; then
      jq -cn \
        --argjson packet "${packet_json}" \
        --arg compact_path "$(jq -r '.compact_path // ""' <<<"${doc_json}")" \
        --arg handoff_packet_path "${packet_path}" \
        --arg handoff_packet_sha256 "$(jq -r '.handoff_packet_sha256 // ""' <<<"${doc_json}")" \
        '$packet + {
          source_compact_path: $compact_path,
          handoff_packet_path: $handoff_packet_path,
          handoff_packet_sha256: $handoff_packet_sha256
        }'
      return 0
    fi
  fi

  jq -cn \
    --arg kind "kernel-handoff-packet" \
    --argjson version 1 \
    --arg run_id "$(jq -r '.run_id // ""' <<<"${doc_json}")" \
    --arg project "$(jq -r '.project // ""' <<<"${doc_json}")" \
    --arg purpose "$(jq -r '.purpose // ""' <<<"${doc_json}")" \
    --arg phase "$(jq -r '.current_phase // ""' <<<"${doc_json}")" \
    --arg mode "$(jq -r '.mode // ""' <<<"${doc_json}")" \
    --arg runtime "$(jq -r '.runtime // ""' <<<"${doc_json}")" \
    --arg lifecycle_state "$(jq -r '.lifecycle_state // ""' <<<"${doc_json}")" \
    --arg updated_at "$(jq -r '.updated_at // ""' <<<"${doc_json}")" \
    --arg next_action "$(jq -r '(.next_action // [])[0] // ""' <<<"${doc_json}")" \
    --arg compact_path "$(jq -r '.compact_path // ""' <<<"${doc_json}")" \
    --arg handoff_packet_path "$(jq -r '.handoff_packet_path // ""' <<<"${doc_json}")" \
    --arg handoff_packet_sha256 "$(jq -r '.handoff_packet_sha256 // ""' <<<"${doc_json}")" \
    --argjson summary "$(jq -c '.summary // []' <<<"${doc_json}")" \
    --argjson decisions "$(jq -c '.decisions // []' <<<"${doc_json}")" \
    --argjson context_reference "$(jq -c '.context_reference // {}' <<<"${doc_json}")" \
    '{
      kind: $kind,
      version: $version,
      run_id: $run_id,
      project: $project,
      purpose: $purpose,
      current_phase: $phase,
      mode: $mode,
      runtime: $runtime,
      lifecycle_state: $lifecycle_state,
      updated_at: $updated_at,
      next_action: $next_action,
      summary: $summary,
      decisions: $decisions,
      source_compact_path: $compact_path,
      handoff_packet_path: $handoff_packet_path,
      handoff_packet_sha256: $handoff_packet_sha256
    }
    + (if ($context_reference | length) == 0 then {} else {context_reference: $context_reference} end)'
}

render_packet_text() {
  local packet_json="${1:?packet json is required}"
  jq -r '
    "Kernel handoff packet:",
    "  - run id: \(.run_id)",
    "  - project: \(.project)",
    "  - purpose: \(.purpose)",
    "  - phase: \(.current_phase)",
    "  - mode: \(.mode)",
    "  - runtime: \(.runtime)",
    "  - lifecycle state: \(.lifecycle_state // "unknown")",
    "  - next action: \(.next_action // "")",
    "  - summary: \((.summary // []) | join(" || "))",
    "  - decisions: \((.decisions // []) | join(" | "))",
    "  - context reference: \(if ((.context_reference // {}) | length) == 0 then "none" else (((.context_reference.label // .context_reference.kind // "context") + " -> " + (.context_reference.path // ""))) end)",
    "  - packet path: \(.handoff_packet_path // "")",
    "  - compact path: \(.source_compact_path // "")"
  ' <<<"${packet_json}"
}

cmd_packet() {
  local format="text"
  local run_filter=""
  local query=""
  local doc_json packet_json search_json

  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --run)
        run_filter="${2:-}"
        [[ -n "${run_filter}" ]] || {
          echo "--run requires a run id" >&2
          exit 2
        }
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        query="${1:-}"
        shift
        if [[ $# -gt 0 ]]; then
          query="${query} $*"
        fi
        break
        ;;
    esac
  done

  if [[ -n "${run_filter}" ]]; then
    doc_json="$(compact_json_for_run "${run_filter}")"
  else
    [[ -n "${query}" ]] || {
      echo "packet requires --run <run_id> or a query" >&2
      exit 2
    }
    search_json="$(cmd_search_json "${query}" 1 "")"
    doc_json="$(jq -c '.results[0] // {}' <<<"${search_json}")"
  fi

  [[ "${doc_json}" != "{}" ]] || {
    echo "no matching run found" >&2
    exit 1
  }

  packet_json="$(packet_json_from_doc "${doc_json}")"
  if [[ "${format}" == "json" ]]; then
    printf '%s\n' "${packet_json}"
    return 0
  fi
  render_packet_text "${packet_json}"
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
          query="${1:-}"
          shift
          if [[ $# -gt 0 ]]; then
            query="${query} $*"
          fi
          break
          ;;
      esac
    done
    [[ -n "${query}" ]] || {
      echo "search requires a query" >&2
      exit 2
    }
    cmd_search "${format}" "${query}" "${limit}" "${run_filter}"
    ;;
  packet)
    shift || true
    cmd_packet "$@"
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
