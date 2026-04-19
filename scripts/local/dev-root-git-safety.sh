#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-verify}"
shift || true

REPO="${DEV_ROOT:-${FUGUE_DEV_ROOT:-${HOME}/Dev}}"
TEMPLATE="${ROOT_DIR}/config/git/dev-root-info-exclude.block"
BEGIN_MARKER="# BEGIN FUGUE DEV ROOT GIT SAFETY"
END_MARKER="# END FUGUE DEV ROOT GIT SAFETY"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/local/dev-root-git-safety.sh [install|verify|audit] [--repo PATH] [--template PATH]

Manages the local .git/info/exclude safety block for a parent Dev repository.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?--repo requires a path}"
      shift 2
      ;;
    --template)
      TEMPLATE="${2:?--template requires a path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

git_dir_for_repo() {
  local repo="${1:?repo is required}"
  local git_dir
  git_dir="$(git -C "${repo}" rev-parse --git-dir)"
  case "${git_dir}" in
    /*) printf '%s\n' "${git_dir}" ;;
    *) printf '%s/%s\n' "${repo}" "${git_dir}" ;;
  esac
}

exclude_path_for_repo() {
  local git_dir
  git_dir="$(git_dir_for_repo "$1")"
  printf '%s/info/exclude\n' "${git_dir}"
}

extract_managed_block() {
  local exclude_path="${1:?exclude path is required}"
  [[ -f "${exclude_path}" ]] || return 0
  awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
    $0 == begin { in_block = 1 }
    in_block { print }
    $0 == end { in_block = 0 }
  ' "${exclude_path}"
}

write_without_managed_block() {
  local exclude_path="${1:?exclude path is required}"
  [[ -f "${exclude_path}" ]] || return 0
  awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "${exclude_path}"
}

install_block() {
  local exclude_path tmp
  exclude_path="$(exclude_path_for_repo "${REPO}")"
  mkdir -p "$(dirname "${exclude_path}")"
  tmp="${exclude_path}.dev-root-git-safety.$$"

  write_without_managed_block "${exclude_path}" | awk '
    NF {
      while (blank_lines > 0) {
        print ""
        blank_lines--
      }
      print
      next
    }
    { blank_lines++ }
  ' > "${tmp}"
  if [[ -s "${tmp}" ]]; then
    printf '\n' >> "${tmp}"
  fi
  cat "${TEMPLATE}" >> "${tmp}"
  printf '\n' >> "${tmp}"

  mv "${tmp}" "${exclude_path}"
  git -C "${REPO}" config --local status.showUntrackedFiles no
  echo "PASS installed managed git safety block: ${exclude_path}"
}

verify_block() {
  local exclude_path expected actual
  exclude_path="$(exclude_path_for_repo "${REPO}")"
  expected="$(cat "${TEMPLATE}")"
  actual="$(extract_managed_block "${exclude_path}")"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL managed block drift: ${exclude_path}" >&2
    diff -u <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") >&2 || true
    return 1
  fi

  if [[ "$(git -C "${REPO}" config --local --get status.showUntrackedFiles 2>/dev/null || true)" != "no" ]]; then
    echo "FAIL status.showUntrackedFiles is not no: ${REPO}" >&2
    return 1
  fi

  if git -C "${REPO}" ls-files --others --exclude-standard | grep -q .; then
    echo "FAIL untracked paths visible to git: ${REPO}" >&2
    return 1
  fi

  echo "PASS verified managed git safety block: ${exclude_path}"
}

audit_block() {
  local exclude_path template_hash actual_hash
  exclude_path="$(exclude_path_for_repo "${REPO}")"
  template_hash="$(shasum -a 256 "${TEMPLATE}" | awk '{print $1}')"
  actual_hash="$(extract_managed_block "${exclude_path}" | shasum -a 256 | awk '{print $1}')"
  printf '{"repo":"%s","exclude":"%s","template_sha256":"%s","actual_block_sha256":"%s"}\n' \
    "${REPO}" "${exclude_path}" "${template_hash}" "${actual_hash}"
}

if [[ ! -d "${REPO}" ]]; then
  echo "Repo path does not exist: ${REPO}" >&2
  exit 2
fi
if ! git -C "${REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: ${REPO}" >&2
  exit 2
fi
if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Template not found: ${TEMPLATE}" >&2
  exit 2
fi

case "${MODE}" in
  install) install_block ;;
  verify) verify_block ;;
  audit) audit_block ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    usage
    exit 2
    ;;
esac
