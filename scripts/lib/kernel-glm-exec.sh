#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
SECRETS_SCRIPT="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"
GLM_BIN="${KERNEL_GLM_BIN:-glm}"
GLM_MODEL="${KERNEL_GLM_MODEL:-${GLM_MODEL:-glm-5.0}}"

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"
export KERNEL_RUN_ID="${RUN_ID}"

usage() {
  cat <<'EOF'
Usage:
  kernel-glm-exec.sh [args...]
EOF
}

ensure_glm_api_key() {
  [[ -n "${ZAI_API_KEY:-}" ]] && return 0
  [[ -f "${SECRETS_SCRIPT}" ]] || return 1

  local exported_line
  exported_line="$(bash "${SECRETS_SCRIPT}" export ZAI_API_KEY 2>/dev/null | head -n 1 || true)"
  [[ -n "${exported_line}" ]] || return 1
  eval "${exported_line}"
  [[ -n "${ZAI_API_KEY:-}" ]]
}

glm_api_extract_prompt() {
  # Extract prompt from various argument patterns:
  #   -p "prompt"  / --prompt "prompt"  (standard)
  #   "raw text"                         (single positional arg)
  #   -m model -p "prompt"              (mixed flags)
  local prompt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--prompt) shift; prompt="${1:-}"; shift ;;
      -m|--model)  shift; shift ;;  # skip model flag (we use our own)
      -t|--temperature) shift; shift ;;
      -h|--help)   return 1 ;;
      --version)   return 1 ;;
      -*)          shift ;;  # skip unknown flags
      *)           [[ -z "${prompt}" ]] && prompt="$1"; shift ;;
    esac
  done
  [[ -n "${prompt}" ]] || return 1
  printf '%s' "${prompt}"
}

run_glm_api_fallback() {
  local prompt
  prompt="$(glm_api_extract_prompt "$@")" || {
    echo "glm api fallback: could not extract prompt from args" >&2
    return 64
  }
  local tmp_dir out_file req http_code content rc model
  local -a candidates=()

  ensure_glm_api_key || {
    echo "glm api fallback requires ZAI_API_KEY" >&2
    return 65
  }
  command -v curl >/dev/null 2>&1 || {
    echo "glm api fallback requires curl" >&2
    return 66
  }
  command -v jq >/dev/null 2>&1 || {
    echo "glm api fallback requires jq" >&2
    return 67
  }

  candidates=("${GLM_MODEL}")
  [[ "${GLM_MODEL}" == "glm-4.5" ]] || candidates+=("glm-4.5")

  tmp_dir="$(mktemp -d)"
  out_file="${tmp_dir}/glm-api-response.json"
  for model in "${candidates[@]}"; do
    req="$(jq -n \
      --arg model "${model}" \
      --arg prompt "${prompt}" \
      '{model:$model,messages:[{role:"user",content:$prompt}],temperature:0.1}')"

    set +e
    http_code="$(curl -sS -o "${out_file}" -w "%{http_code}" "https://api.z.ai/api/coding/paas/v4/chat/completions" \
      --connect-timeout 10 --max-time 60 --retry 1 \
      -H "Authorization: Bearer ${ZAI_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "${req}")"
    rc=$?
    set -e

    if [[ "${rc}" -ne 0 || "${http_code}" != "200" ]]; then
      continue
    fi

    content="$(jq -r '.choices[0].message.content // ""' "${out_file}" 2>/dev/null || true)"
    [[ -n "${content}" ]] || continue
    rm -rf "${tmp_dir}"
    printf '%s\n' "${content}"
    return 0
  done

  [[ -f "${out_file}" ]] && cat "${out_file}" >&2 || true
  rm -rf "${tmp_dir}"
  return 1
}

mark_fail() {
  local note="$1"
  KERNEL_RUN_ID="${RUN_ID}" bash "${GLM_STATE_SCRIPT}" fail "${note}" >/dev/null
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-provider glm failure "${note}" >/dev/null
}

mark_recover() {
  local note="$1"
  KERNEL_RUN_ID="${RUN_ID}" bash "${GLM_STATE_SCRIPT}" recover "${note}" >/dev/null
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-provider glm success "${note}" >/dev/null
}

if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v "${GLM_BIN}" >/dev/null 2>&1; then
  set +e
  run_glm_api_fallback "$@"
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    mark_recover "glm-api-success"
    exit 0
  fi
  if [[ "${KERNEL_GLM_SUBSCRIBED:-false}" == "true" ]]; then
    echo "glm command not on PATH (subscription active, skipping degradation): ${GLM_BIN}" >&2
    exit 127
  fi
  mark_fail "glm-command-missing"
  echo "glm command missing: ${GLM_BIN}" >&2
  exit 127
fi

set +e
"${GLM_BIN}" "$@"
rc=$?
set -e

if [[ "${rc}" -eq 0 ]]; then
  mark_recover "glm-command-success"
else
  mark_fail "glm-command-exit-${rc}"
fi

exit "${rc}"
