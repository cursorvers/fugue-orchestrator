#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/check-notebooklm-runtime-readiness.sh"

failures=0

fail() {
  echo "FAIL [$1]" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS [$1]" >&2
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "${needle}" <<<"${haystack}"; then
    pass "${label}"
  else
    fail "${label}"
    printf 'missing: %s\n%s\n' "${needle}" "${haystack}" >&2
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

make_skill() {
  local base="$1"
  local name="$2"
  mkdir -p "${base}/${name}"
  cat > "${base}/${name}/SKILL.md" <<EOF
---
name: ${name}
description: "desc"
---
EOF
}

codex_dir="${tmpdir}/codex"
claude_dir="${tmpdir}/claude"
mkdir -p "${codex_dir}" "${claude_dir}"
make_skill "${codex_dir}" "notebooklm-shared"
make_skill "${codex_dir}" "notebooklm-visual-brief"
make_skill "${claude_dir}" "notebooklm-shared"
make_skill "${claude_dir}" "notebooklm-visual-brief"

cat > "${tmpdir}/sync-ok.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo sync-ok
EOF
chmod +x "${tmpdir}/sync-ok.sh"

cat > "${tmpdir}/adapter-ok.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action=""
run_dir=""
resolve_only="false"
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --action)
      action="${2:-}"
      shift 2
      ;;
    --run-dir)
      run_dir="${2:-}"
      shift 2
      ;;
    --resolve-only)
      resolve_only="true"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s\n' "${action}:${resolve_only}" >> "${ADAPTER_LOG:?}"

if [[ "${action}" == "smoke" ]]; then
  echo "notebooklm-cli adapter ready"
  exit 0
fi

mkdir -p "${run_dir}/notebooklm"
if [[ "${resolve_only}" == "true" ]]; then
  cat <<'OUT'
nlm notebook create Demo --json
nlm mindmap create NOTEBOOK_ID --confirm --json
OUT
  exit 0
fi

printf '%s' '{"schema_version":"1.0.0","action_intent":"visual-brief","notebook_id":"nb_1","artifact_id":"art_1","artifact_type":"mind_map","raw_output_path":"run/notebooklm/visual.json","is_truncated":false,"sensitivity":"internal","ttl_expires_at":"2026-03-14T00:00:00Z"}' > "${run_dir}/notebooklm/receipt.json"
cat "${run_dir}/notebooklm/receipt.json"
EOF
chmod +x "${tmpdir}/adapter-ok.sh"

off_output="$(
  NOTEBOOKLM_READINESS_SKIP_REPO_TESTS=true \
  NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE=off \
  NOTEBOOKLM_READINESS_ADAPTER_SCRIPT="${tmpdir}/adapter-ok.sh" \
  NOTEBOOKLM_READINESS_SYNC_SCRIPT="${tmpdir}/sync-ok.sh" \
  CODEX_SKILLS_DIR="${codex_dir}" \
  CLAUDE_SKILLS_DIR="${claude_dir}" \
  bash "${SCRIPT}" 2>&1
)"
assert_contains "${off_output}" "==> repo tests skipped (SKIP_REPO_TESTS=true)" "off mode skips repo tests"
assert_contains "${off_output}" "==> live smoke skipped (LIVE_SMOKE_MODE=off)" "off mode skips live smoke"
assert_contains "${off_output}" "notebooklm-runtime-readiness: PASS" "off mode passes"

: > "${tmpdir}/adapter.log"
required_output="$(
  ADAPTER_LOG="${tmpdir}/adapter.log" \
  NOTEBOOKLM_READINESS_SKIP_REPO_TESTS=true \
  NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE=required \
  NOTEBOOKLM_READINESS_EXECUTE_LIVE_MODE=off \
  NOTEBOOKLM_READINESS_ADAPTER_SCRIPT="${tmpdir}/adapter-ok.sh" \
  NOTEBOOKLM_READINESS_SYNC_SCRIPT="${tmpdir}/sync-ok.sh" \
  CODEX_SKILLS_DIR="${codex_dir}" \
  CLAUDE_SKILLS_DIR="${claude_dir}" \
  bash "${SCRIPT}" 2>&1
)"
assert_contains "${required_output}" "==> live smoke: adapter smoke" "required mode runs smoke"
assert_contains "${required_output}" "==> live smoke: resolve-only visual-brief" "required mode runs resolve-only"
assert_contains "${required_output}" "notebooklm-runtime-readiness: PASS" "required mode passes"
assert_contains "$(cat "${tmpdir}/adapter.log")" "smoke:false" "smoke call logged"
assert_contains "$(cat "${tmpdir}/adapter.log")" "visual-brief:true" "resolve-only call logged"

: > "${tmpdir}/adapter.log"
required_live_output="$(
  ADAPTER_LOG="${tmpdir}/adapter.log" \
  NOTEBOOKLM_READINESS_SKIP_REPO_TESTS=true \
  NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE=required \
  NOTEBOOKLM_READINESS_EXECUTE_LIVE_MODE=required \
  NOTEBOOKLM_READINESS_ADAPTER_SCRIPT="${tmpdir}/adapter-ok.sh" \
  NOTEBOOKLM_READINESS_SYNC_SCRIPT="${tmpdir}/sync-ok.sh" \
  CODEX_SKILLS_DIR="${codex_dir}" \
  CLAUDE_SKILLS_DIR="${claude_dir}" \
  bash "${SCRIPT}" 2>&1
)"
assert_contains "${required_live_output}" "==> live smoke: execute visual-brief" "required live mode runs execution"
assert_contains "${required_live_output}" "notebooklm-runtime-readiness: PASS" "required live mode passes"
assert_contains "$(cat "${tmpdir}/adapter.log")" "visual-brief:false" "live execution call logged"

set +e
missing_optional_output="$(
  NOTEBOOKLM_READINESS_SKIP_REPO_TESTS=true \
  NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE=off \
  NOTEBOOKLM_READINESS_REQUIRE_OPTIONAL=true \
  NOTEBOOKLM_READINESS_ADAPTER_SCRIPT="${tmpdir}/adapter-ok.sh" \
  NOTEBOOKLM_READINESS_SYNC_SCRIPT="${tmpdir}/sync-ok.sh" \
  CODEX_SKILLS_DIR="${codex_dir}" \
  CLAUDE_SKILLS_DIR="${claude_dir}" \
  bash "${SCRIPT}" 2>&1
)"
missing_optional_rc=$?
set -e
if [[ "${missing_optional_rc}" -ne 0 ]]; then
  pass "missing optional skill fails"
else
  fail "missing optional skill should fail"
fi
assert_contains "${missing_optional_output}" "missing installed skill" "missing optional skill message"

echo "PASS [check-notebooklm-runtime-readiness]"

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
