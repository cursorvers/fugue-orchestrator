#!/usr/bin/env bash
set -euo pipefail

fugue_default_workspace_roots() {
  local root_dir="${1:?root_dir is required}"
  local approved_tmp_root="${HOME}/Dev/tmp"
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    approved_tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fugue-approved-workspaces"
  fi
  printf '%s:%s\n' "${root_dir}/.fugue" "${approved_tmp_root}"
}

fugue_canonicalize_dir() {
  local dir="${1:?dir is required}"
  mkdir -p "${dir}"
  (
    cd "${dir}" >/dev/null 2>&1
    pwd -P
  )
}

fugue_resolve_target_dir() {
  local target="${1:?target is required}"
  local parent base parent_real suffix next_parent
  parent="$(dirname "${target}")"
  base="$(basename "${target}")"

  suffix=""
  while [[ ! -d "${parent}" ]]; do
    next_parent="$(dirname "${parent}")"
    if [[ "${next_parent}" == "${parent}" ]]; then
      echo "Error: unable to resolve parent directory for target ${target}." >&2
      return 2
    fi
    suffix="/$(basename "${parent}")${suffix}"
    parent="${next_parent}"
  done

  parent_real="$(
    cd "${parent}" >/dev/null 2>&1
    pwd -P
  )"
  printf '%s%s/%s\n' "${parent_real}" "${suffix}" "${base}"
}

fugue_path_within_root() {
  local target="${1:?target is required}"
  local root="${2:?root is required}"
  case "${target}" in
    "${root}"|"${root}"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

fugue_resolve_workspace_dir() {
  local root_dir="${1:?root_dir is required}"
  local target="${2:?target is required}"
  local label="${3:-workspace}"
  local roots_raw target_real
  local roots=()

  roots_raw="${FUGUE_APPROVED_WORKSPACE_ROOTS:-$(fugue_default_workspace_roots "${root_dir}")}"
  target_real="$(fugue_resolve_target_dir "${target}")"

  IFS=':' read -r -a roots <<< "${roots_raw}"
  for root in "${roots[@]}"; do
    local root_trimmed root_real
    root_trimmed="$(printf '%s' "${root}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -n "${root_trimmed}" ]] || continue
    root_real="$(fugue_canonicalize_dir "${root_trimmed}")"
    if fugue_path_within_root "${target_real}" "${root_real}"; then
      printf '%s\n' "${target_real}"
      return 0
    fi
  done

  echo "Error: ${label} must stay within approved workspace roots (${roots_raw}); got ${target_real}." >&2
  return 2
}
