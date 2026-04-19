#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/dev-root-git-safety.sh"

passed=0
failed=0

pass() {
  echo "PASS [$1]"
  passed=$((passed + 1))
}

fail() {
  echo "FAIL [$1]"
  failed=$((failed + 1))
}

assert_success() {
  local name="$1"
  shift
  if "$@" >/tmp/dev-root-git-safety-test.$$ 2>&1; then
    pass "${name}"
  else
    fail "${name}"
    cat /tmp/dev-root-git-safety-test.$$
  fi
}

assert_failure() {
  local name="$1"
  shift
  if "$@" >/tmp/dev-root-git-safety-test.$$ 2>&1; then
    fail "${name}"
    cat /tmp/dev-root-git-safety-test.$$
  else
    pass "${name}"
  fi
}

make_repo() {
  local repo="$1"
  mkdir -p "${repo}"
  git -C "${repo}" init -q
  printf 'custom-cache/\n' > "${repo}/.git/info/exclude"
}

repo_root="${TMPDIR:-/tmp}/dev-root-git-safety-$$"
repo="${repo_root}/repo"
make_repo "${repo}"

echo "=== dev-root-git-safety.sh tests ==="
echo ""

assert_success "install managed block" "${SCRIPT}" install --repo "${repo}"
assert_success "verify installed block" "${SCRIPT}" verify --repo "${repo}"

first_state="$(cat "${repo}/.git/info/exclude")"
assert_success "install idempotent second run" "${SCRIPT}" install --repo "${repo}"
second_state="$(cat "${repo}/.git/info/exclude")"
if [[ "${first_state}" == "${second_state}" ]]; then
  pass "second install leaves exclude unchanged"
else
  fail "second install leaves exclude unchanged"
fi

if grep -Fxq 'custom-cache/' "${repo}/.git/info/exclude"; then
  pass "preserves custom exclude line"
else
  fail "preserves custom exclude line"
fi

awk '
  $0 == "# END FUGUE DEV ROOT GIT SAFETY" { print "# drift inside managed block" }
  { print }
' "${repo}/.git/info/exclude" > "${repo}/.git/info/exclude.drift"
mv "${repo}/.git/info/exclude.drift" "${repo}/.git/info/exclude"
assert_failure "verify detects drift" "${SCRIPT}" verify --repo "${repo}"
assert_success "audit emits json" "${SCRIPT}" audit --repo "${repo}"

echo ""
echo "=== Results: ${passed} passed, ${failed} failed ==="

if (( failed > 0 )); then
  exit 1
fi
