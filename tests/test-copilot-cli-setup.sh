#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/ensure-copilot-cli.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

pass_count=0
fail_count=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS [${label}]"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL [${label}] expected=${expected} actual=${actual}" >&2
    fail_count=$((fail_count + 1))
  fi
}

run_case() {
  local name="$1"
  local mode="$2"
  local token="${3-token}"
  local fake_bin="${TMP_DIR}/${name}/bin"
  local out_file="${TMP_DIR}/${name}/out.env"
  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/copilot" <<EOF
#!/usr/bin/env bash
set -euo pipefail
args="\$*"
if [[ "${mode}" == "ok" ]]; then
  printf 'OK\n'
  exit 0
fi
if [[ "${mode}" == "allow-all-required" ]]; then
  if [[ "\${args}" != *"--allow-all-tools"* ]]; then
    echo "missing allow-all-tools" >&2
    exit 2
  fi
  printf 'OK\n'
  exit 0
fi
printf 'auth failed\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/copilot"
  env -i \
    PATH="${fake_bin}:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="${HOME}" \
    GITHUB_OUTPUT="${out_file}" \
    COPILOT_INSTALL_MODE="never" \
    COPILOT_GITHUB_TOKEN="${token}" \
    bash "${SCRIPT}"
  cat "${out_file}"
}

case_output="$(run_case ok ok)"
assert_eq "available-ok" "available=true" "$(printf '%s\n' "${case_output}" | grep '^available=')"
assert_eq "probe-ok" "probe_ok=true" "$(printf '%s\n' "${case_output}" | grep '^probe_ok=')"
assert_eq "token-type-default" "token_type=unknown" "$(printf '%s\n' "${case_output}" | grep '^token_type=')"

case_output="$(run_case allow-all allow-all-required github_pat_example)"
assert_eq "available-allow-all" "available=true" "$(printf '%s\n' "${case_output}" | grep '^available=')"
assert_eq "reason-allow-all" "reason=probe-ok" "$(printf '%s\n' "${case_output}" | grep '^reason=')"

case_output="$(run_case fail fail)"
assert_eq "available-fail" "available=false" "$(printf '%s\n' "${case_output}" | grep '^available=')"
assert_eq "reason-fail" "reason=probe-failed" "$(printf '%s\n' "${case_output}" | grep '^reason=')"

case_output="$(run_case classic fail ghp_example)"
assert_eq "available-classic" "available=false" "$(printf '%s\n' "${case_output}" | grep '^available=')"
assert_eq "reason-classic" "reason=unsupported-token-type" "$(printf '%s\n' "${case_output}" | grep '^reason=')"
assert_eq "token-type-classic" "token_type=classic_pat" "$(printf '%s\n' "${case_output}" | grep '^token_type=')"

case_output="$(run_case no-token ok "")"
assert_eq "available-no-token" "available=false" "$(printf '%s\n' "${case_output}" | grep '^available=')"
assert_eq "reason-no-token" "reason=missing-token" "$(printf '%s\n' "${case_output}" | grep '^reason=')"

echo
echo "=== Results: ${pass_count} passed, ${fail_count} failed ==="

if (( fail_count > 0 )); then
  exit 1
fi
