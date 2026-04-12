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
  --skill NAME    Skill name (alphanumeric, hyphens, underscores, dots only)
  --run-id ID     Run identifier (default: manual)
  --dry-run       Print eval plan without executing
EOF
}

# S7: validate shift count before shifting
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill)
      [[ $# -ge 2 ]] || { echo "Error: --skill requires a value." >&2; exit 2; }
      skill_name="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || { echo "Error: --run-id requires a value." >&2; exit 2; }
      run_id="$2"
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

# S1: path traversal guard — strict allowlist for skill names
if [[ ! "${skill_name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Error: invalid skill name '${skill_name}'. Only alphanumeric, hyphens, underscores, and dots allowed." >&2
  exit 2
fi

def_file="${ROOT_DIR}/scripts/eval/defs/${skill_name}.yaml"

# S1: additional realpath check to prevent symlink escape
if command -v realpath >/dev/null 2>&1; then
  resolved="$(realpath -m "${def_file}" 2>/dev/null || true)"
  defs_dir="$(realpath -m "${ROOT_DIR}/scripts/eval/defs" 2>/dev/null || true)"
  if [[ -n "${resolved}" && -n "${defs_dir}" && "${resolved}" != "${defs_dir}/"* ]]; then
    echo "Error: skill definition path escapes defs directory." >&2
    exit 2
  fi
fi

if [[ ! -f "${def_file}" ]]; then
  echo "Error: skill definition not found: ${def_file}" >&2
  exit 1
fi

# S6: YAML value parser — split only on first colon to handle URLs and colons in values
# S8: strip surrounding single/double quotes from values
yaml_value() {
  local key="${1:?key is required}"
  local value
  value="$(grep -E "^${key}:" "${def_file}" | sed -E "s/^${key}:[[:space:]]*//" | sed -n '1p')"
  # Strip surrounding quotes ('' or "")
  if [[ "${value}" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  elif [[ "${value}" =~ ^\"(.*)\"$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "${value}"
}

# S3: use shared fugue_json_escape from scratchpad.sh (no local duplicate)

def_skill_name="$(yaml_value "skill_name")"
command_value="$(yaml_value "command")"
timeout_sec="$(yaml_value "timeout_sec")"
expected_exit_code="$(yaml_value "expected_exit_code")"
output_pattern="$(yaml_value "output_pattern")"

if [[ "${dry_run}" == "true" ]]; then
  printf '{"skill":"%s","run_id":"%s","definition_file":"%s","skill_name":"%s","command":"%s","timeout_sec":%s,"expected_exit_code":%s,"output_pattern":"%s"}\n' \
    "$(fugue_json_escape "${skill_name}")" \
    "$(fugue_json_escape "${run_id}")" \
    "$(fugue_json_escape "${def_file}")" \
    "$(fugue_json_escape "${def_skill_name}")" \
    "$(fugue_json_escape "${command_value}")" \
    "${timeout_sec}" \
    "${expected_exit_code}" \
    "$(fugue_json_escape "${output_pattern}")"
  exit 0
fi

scratchpad_init "skill-eval-${skill_name}"

# S5: fail explicitly when no timeout command is available
run_with_timeout() {
  local timeout_value="${1:?timeout is required}"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --preserve-status "${timeout_value}" "$@"
    return
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status "${timeout_value}" "$@"
    return
  fi
  echo "Warning: no timeout command available, running without timeout." >&2
  "$@"
}

output_file="$(mktemp)"
# S4: ensure temp file cleanup on any exit
trap 'rm -f "${output_file}"' EXIT

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
  "$(fugue_json_escape "${run_id}")" \
  "$(fugue_json_escape "${skill_name}")" \
  "$(fugue_json_escape "${def_skill_name}")" \
  "${command_status}" \
  "${expected_exit_code}" \
  "${duration_secs}" \
  "${output_line_count}" \
  "$(fugue_json_escape "${output_pattern}")" >> "${eval_file}"

scratchpad_status="ok"
if [[ "${command_status}" -ne "${expected_exit_code}" ]]; then
  scratchpad_status="error"
fi
scratchpad_log "skill-eval" "${scratchpad_status}" "$(( duration_secs * 1000 ))" "${skill_name}"

if [[ "${command_status}" -ne "${expected_exit_code}" ]]; then
  echo "Error: expected exit code ${expected_exit_code}, got ${command_status}." >&2
  exit 1
fi
