#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/install-kernel-launchers.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_contains() {
  local haystack="${1:?haystack is required}"
  local needle="${2:?needle is required}"
  if ! grep -Fq "${needle}" <<<"${haystack}"; then
    echo "expected output to contain: ${needle}" >&2
    exit 1
  fi
}

assert_symlink_to() {
  local path="${1:?path is required}"
  local expected="${2:?expected target is required}"
  [[ -L "${path}" ]] || {
    echo "expected symlink: ${path}" >&2
    exit 1
  }
  local actual
  actual="$(readlink "${path}")"
  [[ "${actual}" == "${expected}" ]] || {
    echo "unexpected symlink target for ${path}: ${actual}" >&2
    exit 1
  }
}

export HOME="${TMP_DIR}/home-main"
mkdir -p "${HOME}"

install_out="$(bash "${SCRIPT}")"
assert_contains "${install_out}" "installed: ${HOME}/bin/kernel"
assert_contains "${install_out}" "installed: ${HOME}/bin/k4"
assert_contains "${install_out}" "installed: ${HOME}/bin/kernel-root"
assert_contains "${install_out}" "updated: ${HOME}/.zshrc"
for prompt_name in kernel k vote v; do
  assert_contains "${install_out}" "installed: ${HOME}/.codex/prompts/${prompt_name}.md"
done

cmp -s "${ROOT_DIR}/scripts/local/launchers/kernel" "${HOME}/bin/kernel"
cmp -s "${ROOT_DIR}/scripts/local/launchers/k4" "${HOME}/bin/k4"
cmp -s "${ROOT_DIR}/scripts/local/launchers/kernel-root" "${HOME}/bin/kernel-root"
[[ ! -e "${HOME}/bin/codex-kernel-guard" ]] || {
  echo "install should not overwrite or manage existing codex kernel guard" >&2
  exit 1
}
grep -Fqx "[[ -f \"${ROOT_DIR}/scripts/local/launchers/codex-orchestrator.zsh\" ]] && source \"${ROOT_DIR}/scripts/local/launchers/codex-orchestrator.zsh\"" "${HOME}/.zshrc"
for prompt_name in kernel k vote v; do
  assert_symlink_to "${HOME}/.codex/prompts/${prompt_name}.md" "${ROOT_DIR}/.codex/prompts/${prompt_name}.md"
done

check_out="$(bash "${SCRIPT}" --check)"
assert_contains "${check_out}" "kernel launcher: ok"
assert_contains "${check_out}" "k4 launcher: ok"
assert_contains "${check_out}" "kernel-root helper: ok"
assert_contains "${check_out}" "codex kernel guard: missing"
assert_contains "${check_out}" "zshrc snippet: ok"
assert_contains "${check_out}" "codex prompts: ok"

export HOME="${TMP_DIR}/home-prompts-only"
mkdir -p "${HOME}"

prompts_out="$(bash "${SCRIPT}" --prompts-only)"
for prompt_name in kernel k vote v; do
  assert_contains "${prompts_out}" "installed: ${HOME}/.codex/prompts/${prompt_name}.md"
  assert_symlink_to "${HOME}/.codex/prompts/${prompt_name}.md" "${ROOT_DIR}/.codex/prompts/${prompt_name}.md"
done
[[ ! -e "${HOME}/bin/kernel" ]] || {
  echo "prompts-only should not install kernel launcher" >&2
  exit 1
}
[[ ! -e "${HOME}/bin/k4" ]] || {
  echo "prompts-only should not install k4 launcher" >&2
  exit 1
}
[[ ! -e "${HOME}/bin/kernel-root" ]] || {
  echo "prompts-only should not install kernel-root helper" >&2
  exit 1
}
[[ ! -e "${HOME}/bin/codex-kernel-guard" ]] || {
  echo "prompts-only should not install codex kernel guard" >&2
  exit 1
}
[[ ! -e "${HOME}/.zshrc" ]] || {
  echo "prompts-only should not write ~/.zshrc" >&2
  exit 1
}

prompts_check_out="$(bash "${SCRIPT}" --check --prompts-only)"
assert_contains "${prompts_check_out}" "kernel launcher: skipped"
assert_contains "${prompts_check_out}" "k4 launcher: skipped"
assert_contains "${prompts_check_out}" "kernel-root helper: skipped"
assert_contains "${prompts_check_out}" "codex kernel guard: skipped"
assert_contains "${prompts_check_out}" "zshrc snippet: skipped"
assert_contains "${prompts_check_out}" "codex prompts: ok"

echo "install kernel launchers check passed"
