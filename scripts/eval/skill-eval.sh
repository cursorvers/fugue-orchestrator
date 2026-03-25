#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${ROOT_DIR}/scripts/lib/common-utils.sh"
source "${ROOT_DIR}/scripts/lib/scratchpad.sh"

skill_name=""
run_id="manual"
dry_run="false"

usage() {
  cat <<'EOF'
Usage: skill-eval.sh --skill NAME [options]

Options:
  --skill NAME
  --run-id ID
  --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill)
      skill_name="${2:-}"
      shift 2
      ;;
    --run-id)
      run_id="${2:-manual}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${skill_name}" ]]; then
  echo "Error: --skill is required." >&2
  exit 2
fi

def_file="${ROOT_DIR}/scripts/eval/defs/${skill_name}.yaml"
if [[ ! -f "${def_file}" ]]; then
  echo "Error: skill definition not found: ${def_file}" >&2
  exit 1
fi

yaml_value() {
  local key="${1:?key is required}"
  local value
  value="$(grep -E "^${key}:" "${def_file}" | sed -E "s/^${key}:[[:space:]]*//" | sed -n '1p')"
  printf '%s' "${value}"
}

def_skill_name="$(yaml_value "skill_name")"
command_value="$(yaml_value "command")"
timeout_sec="$(yaml_value "timeout_sec")"
expected_exit_code="$(yaml_value "expected_exit_code")"
output_pattern="$(yaml_value "output_pattern")"

if [[ "${dry_run}" == "true" ]]; then
  printf '{"skill":"%s","run_id":"%s","definition_file":"%s","skill_name":"%s","command":"%s","timeout_sec":%s,"expected_exit_code":%s,"output_pattern":"%s"}\n' \
    "${skill_name}" \
    "${run_id}" \
    "${def_file}" \
    "${def_skill_name}" \
    "${command_value}" \
    "${timeout_sec}" \
    "${expected_exit_code}" \
    "${output_pattern}"
  exit 0
fi

scratchpad_init "skill-eval-${skill_name}"

run_with_timeout() {
  local timeout_value="${1:?timeout is required}"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status "${timeout_value}" "$@"
    return
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --preserve-status "${timeout_value}" "$@"
    return
  fi
  "$@"
}

output_file="$(mktemp)"
start_epoch="$(date +%s)"
if run_with_timeout "${timeout_sec}" bash -lc "${command_value}" >"${output_file}" 2>&1; then
  command_status=0
else
  command_status="$?"
fi
end_epoch="$(date +%s)"

duration_secs=$(( end_epoch - start_epoch ))
output_line_count="$(wc -l < "${output_file}" | tr -d '[:space:]')"

eval_dir="${ROOT_DIR}/.fugue/eval"
mkdir -p "${eval_dir}"
eval_file="${eval_dir}/$(date -u +%Y-%m-%d)_${skill_name}.jsonl"

printf '{"ts":"%s","run_id":"%s","skill":"%s","definition_skill_name":"%s","exit_code":%s,"expected_exit_code":%s,"duration_secs":%s,"output_line_count":%s,"output_pattern":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "${run_id}" \
  "${skill_name}" \
  "${def_skill_name}" \
  "${command_status}" \
  "${expected_exit_code}" \
  "${duration_secs}" \
  "${output_line_count}" \
  "${output_pattern}" >> "${eval_file}"

scratchpad_status="ok"
if [[ "${command_status}" -ne "${expected_exit_code}" ]]; then
  scratchpad_status="error"
fi
scratchpad_log "skill-eval" "${scratchpad_status}" "$(( duration_secs * 1000 ))" "${skill_name}"

rm -f "${output_file}"

if [[ "${command_status}" -ne "${expected_exit_code}" ]]; then
  echo "Error: expected exit code ${expected_exit_code}, got ${command_status}." >&2
  exit "${command_status}"
fi
