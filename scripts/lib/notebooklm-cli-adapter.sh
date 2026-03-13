#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./notebooklm-bin.sh
source "${SCRIPT_DIR}/notebooklm-bin.sh"

action=""
format="json"
title=""
prompt=""
source_manifest=""
artifact_type="mind_map"
orientation="landscape"
style="professional"
notebook_id=""
run_dir=""
sensitivity="internal"
ttl_hours="24"
ok_to_execute="false"
human_approved="false"
resolve_only="false"
dry_run="false"
nlm_bin_requested="${NLM_BIN:-${FUGUE_NOTEBOOKLM_BIN:-nlm}}"
nlm_bin=""
nlm_display=""

usage() {
  cat <<'EOF'
Usage: notebooklm-cli-adapter.sh --action <id> [options]

Actions:
  smoke
  visual-brief
  slide-prep

Options:
  --title <text>                   Notebook title when creating a notebook.
  --prompt <text>                  Optional prompt or focus text.
  --source-manifest <path>         JSON file describing source inputs.
  --artifact-type <mind_map>
                                   Artifact type for visual-brief.
  --notebook-id <id>               Reuse an existing notebook instead of creating one.
  --run-dir <path>                 Write raw outputs and receipt metadata under <run-dir>/notebooklm.
  --sensitivity <public|internal|restricted>
                                   Sensitivity label for the bounded receipt.
  --ttl-hours <n>                  TTL in hours for fetched artifacts (default: 24).
  --ok-to-execute <true|false>     Gate external create actions on Kernel approval state.
  --human-approved <true|false>    Gate external create actions on explicit human approval.
  --resolve-only                   Print resolved commands and exit.
  --dry-run                        Alias for --resolve-only.
  --format <json|table>            Output format (default: json).
  -h, --help                       Show this help.

Source manifest format:
{
  "sources": [
    {"type": "url", "value": "https://example.com", "wait": true},
    {"type": "file", "value": "/path/doc.pdf", "wait": true},
    {"type": "text", "value": "inline notes", "title": "Notes"},
    {"type": "youtube", "value": "https://youtube.com/..."},
    {"type": "drive", "value": "document-id"}
  ]
}
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_non_empty() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" ]] || fail "${label} is required"
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

validate_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail "expected positive integer, got: $1"
}

print_command() {
  local cmd=("$@")
  printf '%q' "${cmd[0]}"
  local i
  for (( i = 1; i < ${#cmd[@]}; i++ )); do
    printf ' %q' "${cmd[i]}"
  done
  printf '\n'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)
        action="${2:-}"
        shift 2
        ;;
      --title)
        title="${2:-}"
        shift 2
        ;;
      --prompt)
        prompt="${2:-}"
        shift 2
        ;;
      --source-manifest)
        source_manifest="${2:-}"
        shift 2
        ;;
      --artifact-type)
        artifact_type="${2:-mind_map}"
        shift 2
        ;;
      --orientation)
        orientation="${2:-landscape}"
        shift 2
        ;;
      --style)
        style="${2:-professional}"
        shift 2
        ;;
      --notebook-id)
        notebook_id="${2:-}"
        shift 2
        ;;
      --run-dir)
        run_dir="${2:-}"
        shift 2
        ;;
      --sensitivity)
        sensitivity="${2:-internal}"
        shift 2
        ;;
      --ttl-hours)
        ttl_hours="${2:-24}"
        shift 2
        ;;
      --ok-to-execute)
        ok_to_execute="${2:-false}"
        shift 2
        ;;
      --human-approved)
        human_approved="${2:-false}"
        shift 2
        ;;
      --resolve-only)
        resolve_only="true"
        shift
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --format)
        format="${2:-json}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done
}

json_get() {
  local path="$1"
  local filter="$2"
  jq -r "${filter}" "${path}"
}

parse_id_from_output() {
  local path="$1"
  local kind="$2"
  local value=""

  if jq -e . >/dev/null 2>&1 < "${path}"; then
    case "${kind}" in
      notebook)
        value="$(jq -r '.id // .notebook_id // .notebookId // empty' "${path}")"
        ;;
      artifact)
        value="$(jq -r '.id // .artifact_id // .artifactId // .studioId // empty' "${path}")"
        ;;
      source)
        value="$(jq -r '.id // .source_id // .sourceId // empty' "${path}")"
        ;;
    esac
  fi

  if [[ -z "${value}" ]]; then
    case "${kind}" in
      notebook)
        value="$(sed -nE 's/^[[:space:]]*ID:[[:space:]]*([^[:space:]]+).*$/\1/p' "${path}" | head -n1)"
        ;;
      artifact)
        value="$(sed -nE 's/^[[:space:]]*Artifact ID:[[:space:]]*([^[:space:]]+).*$/\1/p' "${path}" | head -n1)"
        if [[ -z "${value}" ]]; then
          value="$(sed -nE 's/^[[:space:]]*ID:[[:space:]]*([^[:space:]]+).*$/\1/p' "${path}" | head -n1)"
        fi
        ;;
      source)
        value="$(sed -nE 's/^[[:space:]]*Source ID:[[:space:]]*([^[:space:]]+).*$/\1/p' "${path}" | head -n1)"
        if [[ -z "${value}" ]]; then
          value="$(sed -nE 's/^[[:space:]]*ID:[[:space:]]*([^[:space:]]+).*$/\1/p' "${path}" | head -n1)"
        fi
        ;;
    esac
  fi

  printf '%s' "${value}"
}

build_receipt() {
  local notebook_id_value="$1"
  local artifact_id_value="$2"
  local artifact_type_value="$3"
  local raw_output_path_value="$4"
  local receipt_path="$5"
  local ttl_expires_at

  ttl_expires_at="$(date -u -v+"${ttl_hours}"H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 - <<PY
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) + timedelta(hours=${ttl_hours})).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"

  jq -n \
    --arg schema_version "1.0.0" \
    --arg action_intent "${action}" \
    --arg notebook_id "${notebook_id_value}" \
    --arg artifact_id "${artifact_id_value}" \
    --arg artifact_type "${artifact_type_value}" \
    --arg raw_output_path "${raw_output_path_value}" \
    --arg sensitivity "${sensitivity}" \
    --arg ttl_expires_at "${ttl_expires_at}" \
    '{
      schema_version:$schema_version,
      action_intent:$action_intent,
      notebook_id:$notebook_id,
      artifact_id:$artifact_id,
      artifact_type:$artifact_type,
      raw_output_path:$raw_output_path,
      is_truncated:false,
      sensitivity:$sensitivity,
      ttl_expires_at:$ttl_expires_at
    }' > "${receipt_path}"
}

commands=()
note_dir=""
receipt_path=""
meta_output_path=""
stderr_output_path=""
command_log_path=""

record_command() {
  local cmd=("$@")
  if [[ -n "${nlm_bin:-}" && -n "${nlm_display:-}" && "${cmd[0]}" == "${nlm_bin}" ]]; then
    cmd[0]="${nlm_display}"
  fi
  commands+=("$(print_command "${cmd[@]}")")
}

write_meta() {
  local status="$1"
  local exit_code="$2"
  local message="$3"
  local receipt_file="${4:-}"
  [[ -n "${meta_output_path}" ]] || return 0

  jq -n \
    --arg action "${action}" \
    --arg status "${status}" \
    --arg message "${message}" \
    --arg format "${format}" \
    --arg source_manifest "${source_manifest}" \
    --arg sensitivity "${sensitivity}" \
    --arg notebook_id "${notebook_id}" \
    --arg receipt_path "${receipt_file}" \
    --argjson commands "$(printf '%s\n' "${commands[@]}" | jq -R . | jq -s .)" \
    --argjson exit_code "${exit_code}" \
    '{
      action:$action,
      status:$status,
      message:$message,
      format:$format,
      source_manifest:(if $source_manifest == "" then null else $source_manifest end),
      sensitivity:$sensitivity,
      notebook_id:(if $notebook_id == "" then null else $notebook_id end),
      receipt_path:(if $receipt_path == "" then null else $receipt_path end),
      commands:$commands,
      exit_code:$exit_code
    }' > "${meta_output_path}"
}

run_cmd() {
  local stdout_path="$1"
  local stderr_path="$2"
  shift 2
  record_command "$@"
  set +e
  "$@" > "${stdout_path}" 2> "${stderr_path}"
  local rc=$?
  set -e
  return "${rc}"
}

ensure_run_dir() {
  [[ -n "${run_dir}" ]] || return 0
  if [[ "${run_dir}" != /* ]]; then
    run_dir="$(cd "${PWD}" && pwd)/${run_dir}"
  fi
  note_dir="${run_dir%/}/notebooklm"
  mkdir -p "${note_dir}"
  receipt_path="${note_dir}/receipt.json"
  meta_output_path="${note_dir}/${action}-meta.json"
  stderr_output_path="${note_dir}/${action}.stderr.log"
  command_log_path="${note_dir}/${action}.commands.txt"
}

validate_inputs() {
  [[ -n "${action}" ]] || fail "--action is required"
  case "${action}" in
    smoke|visual-brief|slide-prep) ;;
    *)
      fail "unsupported --action=${action}"
      ;;
  esac

  case "${format}" in
    json|table) ;;
    *)
      fail "invalid --format=${format}"
      ;;
  esac

  case "${sensitivity}" in
    public|internal|restricted) ;;
    *)
      fail "invalid --sensitivity=${sensitivity}"
      ;;
  esac

  validate_positive_int "${ttl_hours}"
  ok_to_execute="$(normalize_bool "${ok_to_execute}")"
  human_approved="$(normalize_bool "${human_approved}")"
  if [[ "${dry_run}" == "true" ]]; then
    resolve_only="true"
  fi

  if [[ "${action}" == "visual-brief" ]]; then
    case "${artifact_type}" in
      mind_map) ;;
      *)
        fail "visual-brief currently supports only mind_map"
        ;;
    esac
  fi

  if [[ "${action}" == "visual-brief" || "${action}" == "slide-prep" ]]; then
    [[ -n "${notebook_id}" || -n "${title}" ]] || fail "--title or --notebook-id is required"
    require_non_empty "${source_manifest}" "--source-manifest"
    [[ -f "${source_manifest}" ]] || fail "source manifest not found: ${source_manifest}"
    jq empty "${source_manifest}" >/dev/null 2>&1 || fail "source manifest is not valid JSON: ${source_manifest}"
  fi

  nlm_bin="$(notebooklm_resolve_bin "${nlm_bin_requested}")" || exit 1
  nlm_display="$(basename "${nlm_bin}")"
}

source_count() {
  jq 'if type == "array" then length else (.sources // [] | length) end' "${source_manifest}"
}

iter_sources() {
  jq -c 'if type == "array" then .[] else (.sources // [])[] end' "${source_manifest}"
}

emit_commands() {
  printf '%s\n' "${commands[@]}"
}

build_source_command() {
  local notebook_ref="$1"
  local source_json="$2"
  local source_type value
  source_type="$(jq -r '.type // empty' <<<"${source_json}")"
  value="$(jq -r '.value // .url // .file // .text // .youtube // .drive // empty' <<<"${source_json}")"

  case "${source_type}" in
    url)
      cmd=("${nlm_bin}" add "${notebook_ref}" "${value}")
      ;;
    file)
      [[ -f "${value}" ]] || fail "source file not found: ${value}"
      cmd=("${nlm_bin}" add "${notebook_ref}" "${value}")
      ;;
    text)
      cmd=("${nlm_bin}" add "${notebook_ref}" "${value}")
      ;;
    youtube)
      cmd=("${nlm_bin}" add "${notebook_ref}" "${value}")
      ;;
    drive)
      cmd=("${nlm_bin}" add "${notebook_ref}" "${value}")
      ;;
    *)
      fail "unsupported source type in manifest: ${source_type}"
      ;;
  esac
}

write_command_log() {
  [[ -n "${command_log_path}" ]] || return 0
  emit_commands > "${command_log_path}"
}

main() {
  parse_args "$@"
  validate_inputs
  ensure_run_dir

  case "${action}" in
    smoke)
      record_command "${nlm_bin}" --help
      if [[ "${resolve_only}" == "true" ]]; then
        write_command_log
        write_meta "resolved" 0 "resolved command"
        emit_commands
        exit 0
      fi
      if "${nlm_bin}" --help >/dev/null 2>&1; then
        write_command_log
        write_meta "ok" 0 "adapter ready"
        echo "notebooklm-cli adapter ready"
        exit 0
      fi
      write_command_log
      write_meta "error" 1 "adapter check failed"
      exit 1
      ;;
  esac

  if [[ "${ok_to_execute}" != "true" || "${human_approved}" != "true" ]]; then
    record_command "# blocked by approval gate"
    write_command_log
    write_meta "skipped" 4 "artifact creation blocked by approval gate"
    echo "ERROR: approval gate requires --ok-to-execute true and --human-approved true" >&2
    exit 4
  fi

  local notebook_ref="${notebook_id}"
  local notebook_create_stdout="${note_dir}/notebook-create.json"
  local notebook_create_stderr="${note_dir}/notebook-create.stderr.log"
  local artifact_stdout="${note_dir}/${action}.json"
  local artifact_stderr="${note_dir}/${action}.stderr.log"

  if [[ -z "${note_dir}" ]]; then
    local tmp_root
    tmp_root="$(mktemp -d "/Users/masayuki/Dev/tmp/notebooklm-adapter.XXXXXX")"
    trap 'rm -rf "${tmp_root}"' EXIT
    note_dir="${tmp_root}"
    receipt_path="${tmp_root}/receipt.json"
    notebook_create_stdout="${tmp_root}/notebook-create.json"
    notebook_create_stderr="${tmp_root}/notebook-create.stderr.log"
    artifact_stdout="${tmp_root}/${action}.json"
    artifact_stderr="${tmp_root}/${action}.stderr.log"
  fi

  if [[ -z "${notebook_ref}" ]]; then
    create_cmd=("${nlm_bin}" create "${title}")
    if [[ "${resolve_only}" == "true" ]]; then
      record_command "${create_cmd[@]}"
      notebook_ref="NOTEBOOK_ID"
    else
      run_cmd "${notebook_create_stdout}" "${notebook_create_stderr}" "${create_cmd[@]}" || {
        write_command_log
        write_meta "error" 1 "notebook create failed"
        [[ -s "${notebook_create_stderr}" ]] && cat "${notebook_create_stderr}" >&2
        exit 1
      }
      notebook_ref="$(parse_id_from_output "${notebook_create_stdout}" notebook)"
      [[ -n "${notebook_ref}" ]] || fail "could not resolve notebook id from notebook create output"
    fi
  fi

  local -a source_refs=()
  local source_counter=0
  while IFS= read -r source_json; do
    [[ -n "${source_json}" ]] || continue
    build_source_command "${notebook_ref}" "${source_json}"
    if [[ "${resolve_only}" == "true" ]]; then
      record_command "${cmd[@]}"
      source_counter=$((source_counter + 1))
      source_refs+=("SOURCE_ID_${source_counter}")
      continue
    fi

    local source_id
    source_counter=$((source_counter + 1))
    local source_stdout="${note_dir}/source-${source_counter}.json"
    local source_stderr="${note_dir}/source-${source_counter}.stderr.log"
    run_cmd "${source_stdout}" "${source_stderr}" "${cmd[@]}" || {
      write_command_log
      write_meta "error" 1 "source add failed"
      [[ -s "${source_stderr}" ]] && cat "${source_stderr}" >&2
      exit 1
    }
    source_id="$(parse_id_from_output "${source_stdout}" source)"
    [[ -n "${source_id}" ]] || fail "could not resolve source id from source add output"
    source_refs+=("${source_id}")
  done < <(iter_sources)

  local final_artifact_type="${artifact_type}"
  case "${action}" in
    visual-brief)
      artifact_cmd=("${nlm_bin}" mindmap "${notebook_ref}" "${source_refs[@]}")
      ;;
    slide-prep)
      final_artifact_type="report"
      artifact_cmd=("${nlm_bin}" briefing-doc "${notebook_ref}" "${source_refs[@]}")
      ;;
  esac

  if [[ "${resolve_only}" == "true" ]]; then
    record_command "${artifact_cmd[@]}"
    write_command_log
    write_meta "resolved" 0 "resolved commands"
    emit_commands
    exit 0
  fi

  run_cmd "${artifact_stdout}" "${artifact_stderr}" "${artifact_cmd[@]}" || {
    write_command_log
    write_meta "error" 1 "artifact creation failed"
    [[ -s "${artifact_stderr}" ]] && cat "${artifact_stderr}" >&2
    exit 1
  }

  local artifact_id
  artifact_id="$(parse_id_from_output "${artifact_stdout}" artifact)"
  [[ -n "${artifact_id}" ]] || fail "could not resolve artifact id from artifact output"

  build_receipt "${notebook_ref}" "${artifact_id}" "${final_artifact_type}" "${artifact_stdout}" "${receipt_path}"
  write_command_log
  write_meta "ok" 0 "artifact created" "${receipt_path}"

  if [[ "${format}" == "table" ]]; then
    jq -r '"action_intent=\(.action_intent)\nnotebook_id=\(.notebook_id)\nartifact_id=\(.artifact_id)\nartifact_type=\(.artifact_type)\nraw_output_path=\(.raw_output_path)"' "${receipt_path}"
  else
    cat "${receipt_path}"
  fi
}

main "$@"
