#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOME_BIN="${HOME}/bin"
ZSHRC_PATH="${HOME}/.zshrc"
CODEX_PROMPTS_DIR="${HOME}/.codex/prompts"
KERNEL_TARGET="${HOME_BIN}/kernel"
K4_TARGET="${HOME_BIN}/k4"
KERNEL_SOURCE="${ROOT_DIR}/scripts/local/launchers/kernel"
K4_SOURCE="${ROOT_DIR}/scripts/local/launchers/k4"
SNIPPET_SOURCE="${ROOT_DIR}/scripts/local/launchers/codex-orchestrator.zsh"
SNIPPET_LINE="[[ -f \"${SNIPPET_SOURCE}\" ]] && source \"${SNIPPET_SOURCE}\""
PROMPT_NAMES=(kernel k vote v)

usage() {
  cat <<'EOF'
Usage:
  install-kernel-launchers.sh [--check] [--skip-zshrc] [--skip-prompts] [--prompts-only]

Options:
  --check       Validate installed launcher/snippet state without modifying files.
  --skip-zshrc  Install kernel launcher only and do not touch ~/.zshrc.
  --skip-prompts
                Do not install ~/.codex/prompts entries for /kernel, /k, /vote, and /v.
  --prompts-only
                Install ~/.codex/prompts entries only and skip launcher/.zshrc changes.
EOF
}

CHECK_ONLY=false
SKIP_ZSHRC=false
SKIP_PROMPTS=false
PROMPTS_ONLY=false

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --check)
      CHECK_ONLY=true
      shift
      ;;
    --skip-zshrc)
      SKIP_ZSHRC=true
      shift
      ;;
    --skip-prompts)
      SKIP_PROMPTS=true
      shift
      ;;
    --prompts-only)
      PROMPTS_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -f "${KERNEL_SOURCE}" ]] || {
  echo "missing kernel entrypoint source: ${KERNEL_SOURCE}" >&2
  exit 1
}
[[ -f "${K4_SOURCE}" ]] || {
  echo "missing k4 launcher source: ${K4_SOURCE}" >&2
  exit 1
}
[[ -f "${SNIPPET_SOURCE}" ]] || {
  echo "missing codex snippet source: ${SNIPPET_SOURCE}" >&2
  exit 1
}
for prompt_name in "${PROMPT_NAMES[@]}"; do
  [[ -f "${ROOT_DIR}/.codex/prompts/${prompt_name}.md" ]] || {
    echo "missing prompt source: ${ROOT_DIR}/.codex/prompts/${prompt_name}.md" >&2
    exit 1
  }
done

kernel_matches() {
  cmp -s "${KERNEL_SOURCE}" "${KERNEL_TARGET}"
}

k4_matches() {
  cmp -s "${K4_SOURCE}" "${K4_TARGET}"
}

snippet_installed() {
  [[ -f "${ZSHRC_PATH}" ]] && grep -Fqx "${SNIPPET_LINE}" "${ZSHRC_PATH}"
}

prompt_source_path() {
  local prompt_name="${1:?prompt name is required}"
  printf '%s/.codex/prompts/%s.md\n' "${ROOT_DIR}" "${prompt_name}"
}

prompt_target_path() {
  local prompt_name="${1:?prompt name is required}"
  printf '%s/%s.md\n' "${CODEX_PROMPTS_DIR}" "${prompt_name}"
}

prompt_matches() {
  local prompt_name="${1:?prompt name is required}"
  local source_path target_path
  source_path="$(prompt_source_path "${prompt_name}")"
  target_path="$(prompt_target_path "${prompt_name}")"
  [[ -f "${target_path}" ]] || return 1
  cmp -s "${source_path}" "${target_path}"
}

install_prompt() {
  local prompt_name="${1:?prompt name is required}"
  local source_path target_path
  source_path="$(prompt_source_path "${prompt_name}")"
  target_path="$(prompt_target_path "${prompt_name}")"
  ln -sfn "${source_path}" "${target_path}"
}

print_prompt_check_status() {
  local missing=0 prompt_name
  for prompt_name in "${PROMPT_NAMES[@]}"; do
    if ! prompt_matches "${prompt_name}"; then
      missing=1
      break
    fi
  done
  if (( missing == 0 )); then
    echo "codex prompts: ok"
  else
    echo "codex prompts: drift"
  fi
}

if [[ "${CHECK_ONLY}" == "true" ]]; then
  if [[ "${PROMPTS_ONLY}" == "true" ]]; then
    echo "kernel launcher: skipped"
    echo "k4 launcher: skipped"
  else
    kernel_matches && echo "kernel launcher: ok" || echo "kernel launcher: drift"
    k4_matches && echo "k4 launcher: ok" || echo "k4 launcher: drift"
  fi
  if [[ "${PROMPTS_ONLY}" == "true" || "${SKIP_ZSHRC}" == "true" ]]; then
    echo "zshrc snippet: skipped"
  elif snippet_installed; then
    echo "zshrc snippet: ok"
  else
    echo "zshrc snippet: missing"
  fi
  if [[ "${SKIP_PROMPTS}" == "true" ]]; then
    echo "codex prompts: skipped"
  else
    print_prompt_check_status
  fi
  exit 0
fi

if [[ "${PROMPTS_ONLY}" != "true" ]]; then
  mkdir -p "${HOME_BIN}"
  install -m 0755 "${KERNEL_SOURCE}" "${KERNEL_TARGET}"
  echo "installed: ${KERNEL_TARGET}"
  install -m 0755 "${K4_SOURCE}" "${K4_TARGET}"
  echo "installed: ${K4_TARGET}"
fi

if [[ "${PROMPTS_ONLY}" != "true" && "${SKIP_ZSHRC}" != "true" ]]; then
  touch "${ZSHRC_PATH}"
  if ! snippet_installed; then
    printf '\n%s\n' "${SNIPPET_LINE}" >> "${ZSHRC_PATH}"
    echo "updated: ${ZSHRC_PATH}"
  else
    echo "zshrc snippet already present"
  fi
fi

if [[ "${SKIP_PROMPTS}" != "true" ]]; then
  mkdir -p "${CODEX_PROMPTS_DIR}"
  for prompt_name in "${PROMPT_NAMES[@]}"; do
    install_prompt "${prompt_name}"
    echo "installed: $(prompt_target_path "${prompt_name}")"
  done
fi
