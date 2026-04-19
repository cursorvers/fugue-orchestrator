#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/dirty-worktree-summary.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "${needle}" <<< "${haystack}"; then
    echo "PASS [${label}]"
  else
    echo "FAIL [${label}]: missing ${needle}" >&2
    echo "${haystack}" >&2
    exit 1
  fi
}

git -C "${tmpdir}" init -q
git -C "${tmpdir}" config user.email test@example.invalid
git -C "${tmpdir}" config user.name test
printf 'base\n' > "${tmpdir}/tracked.txt"
git -C "${tmpdir}" add tracked.txt
git -C "${tmpdir}" commit -q -m init

clean_output="$(cd "${tmpdir}" && bash "${SCRIPT}")"
assert_contains "${clean_output}" "- state: clean" "clean-state"
assert_contains "${clean_output}" "- tracked_modified: 0" "clean-modified-zero"

printf 'changed\n' > "${tmpdir}/tracked.txt"
printf 'new\n' > "${tmpdir}/untracked.txt"

dirty_output="$(cd "${tmpdir}" && bash "${SCRIPT}")"
assert_contains "${dirty_output}" "- state: dirty" "dirty-state"
assert_contains "${dirty_output}" "- tracked_modified: 1" "tracked-modified-count"
assert_contains "${dirty_output}" "- untracked: 1" "untracked-count"
assert_contains "${dirty_output}" "- entries:" "entries-heading"
assert_contains "${dirty_output}" "tracked.txt" "entries-include-tracked"
assert_contains "${dirty_output}" "untracked.txt" "entries-include-untracked"

git -C "${tmpdir}" add tracked.txt
staged_output="$(cd "${tmpdir}" && bash "${SCRIPT}")"
assert_contains "${staged_output}" "- staged: 1" "staged-count"

limited_output="$(cd "${tmpdir}" && bash "${SCRIPT}" --max-entries 1)"
assert_contains "${limited_output}" "... 2 total entries" "limited-entry-count"

echo "PASS [dirty-worktree-summary]"
