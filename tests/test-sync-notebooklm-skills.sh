#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/scripts/skills/sync-notebooklm-skills.sh"
PROFILE_DOC="${SCRIPT_DIR}/docs/notebooklm-skills-profile.md"
MANIFEST="${SCRIPT_DIR}/config/skills/notebooklm-cli-baseline.tsv"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

make_skill() {
  local root="$1"
  local name="$2"
  local description="$3"

  mkdir -p "${root}/${name}"
  cat > "${root}/${name}/SKILL.md" <<EOF
---
name: ${name}
description: "${description}"
---

# ${name}
EOF
}

assert_ok() {
  local test_name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${test_name}]"
    failed=$((failed + 1))
  fi
}

test_required_only() {
  local skills_root="${tmp_dir}/skills-required"
  local manifest="${tmp_dir}/manifest-required.tsv"
  local codex_dir="${tmp_dir}/codex-required"
  local claude_dir="${tmp_dir}/claude-required"

  make_skill "${skills_root}" "alpha-required" "required skill"
  make_skill "${skills_root}" "beta-optional" "optional skill"
  cat > "${manifest}" <<'EOF'
# skill_id	profile	rationale
alpha-required	required	alpha
beta-optional	optional	beta
EOF

  env CODEX_SKILLS_DIR="${codex_dir}" CLAUDE_SKILLS_DIR="${claude_dir}" \
    bash "${SYNC_SCRIPT}" \
      --manifest "${manifest}" \
      --skills-root "${skills_root}" \
      --target both >/dev/null

  test -d "${codex_dir}/alpha-required" &&
    test -d "${claude_dir}/alpha-required" &&
    test ! -e "${codex_dir}/beta-optional" &&
    test ! -e "${claude_dir}/beta-optional"
}

test_with_optional_and_target_routing() {
  local skills_root="${tmp_dir}/skills-optional"
  local manifest="${tmp_dir}/manifest-optional.tsv"
  local codex_dir="${tmp_dir}/codex-optional"
  local claude_dir="${tmp_dir}/claude-optional"

  make_skill "${skills_root}" "alpha-required" "required skill"
  make_skill "${skills_root}" "beta-optional" "optional skill"
  cat > "${manifest}" <<'EOF'
# skill_id	profile	rationale
alpha-required	required	alpha
beta-optional	optional	beta
EOF

  env CODEX_SKILLS_DIR="${codex_dir}" CLAUDE_SKILLS_DIR="${claude_dir}" \
    bash "${SYNC_SCRIPT}" \
      --manifest "${manifest}" \
      --skills-root "${skills_root}" \
      --target codex \
      --with-optional >/dev/null

  test -d "${codex_dir}/alpha-required" &&
    test -d "${codex_dir}/beta-optional" &&
    test ! -e "${claude_dir}/alpha-required"
}

test_dry_run_and_unmanaged_protection() {
  local skills_root="${tmp_dir}/skills-dry"
  local manifest="${tmp_dir}/manifest-dry.tsv"
  local codex_dir="${tmp_dir}/codex-dry"
  local claude_dir="${tmp_dir}/claude-dry"
  local output

  make_skill "${skills_root}" "alpha-required" "required skill"
  cat > "${manifest}" <<'EOF'
# skill_id	profile	rationale
alpha-required	required	alpha
EOF

  mkdir -p "${codex_dir}/alpha-required"
  printf 'user-data\n' > "${codex_dir}/alpha-required/local.txt"

  output="$(env CODEX_SKILLS_DIR="${codex_dir}" CLAUDE_SKILLS_DIR="${claude_dir}" \
    bash "${SYNC_SCRIPT}" \
      --manifest "${manifest}" \
      --skills-root "${skills_root}" \
      --target codex \
      --dry-run)"

  grep -q 'SKIP .*exists and not managed' <<<"${output}" &&
    test -f "${codex_dir}/alpha-required/local.txt" &&
    test ! -e "${claude_dir}/alpha-required"
}

test_payload_validation() {
  local skills_root="${tmp_dir}/skills-bad"
  local manifest="${tmp_dir}/manifest-bad.tsv"
  local stderr_path="${tmp_dir}/payload.stderr"

  mkdir -p "${skills_root}/bad-skill"
  cat > "${skills_root}/bad-skill/SKILL.md" <<'EOF'
---
name: bad-skill
---

# bad-skill
EOF
  cat > "${manifest}" <<'EOF'
# skill_id	profile	rationale
bad-skill	required	bad
EOF

  if bash "${SYNC_SCRIPT}" \
    --manifest "${manifest}" \
    --skills-root "${skills_root}" \
    --target both > /dev/null 2>"${stderr_path}"; then
    return 1
  fi

  grep -q 'has no description in frontmatter' "${stderr_path}"
}

test_managed_replace_and_profile_manifest_drift() {
  local skills_root="${tmp_dir}/skills-managed"
  local manifest="${tmp_dir}/manifest-managed.tsv"
  local codex_dir="${tmp_dir}/codex-managed"
  local marker=".fugue-managed-notebooklm"
  local output

  make_skill "${skills_root}" "alpha-required" "required skill"
  cat > "${manifest}" <<'EOF'
# skill_id	profile	rationale
alpha-required	required	alpha
EOF

  mkdir -p "${codex_dir}/alpha-required"
  printf 'old\n' > "${codex_dir}/alpha-required/local.txt"
  printf 'managed\n' > "${codex_dir}/alpha-required/${marker}"

  output="$(env CODEX_SKILLS_DIR="${codex_dir}" CLAUDE_SKILLS_DIR="${tmp_dir}/claude-managed" \
    bash "${SYNC_SCRIPT}" \
      --manifest "${manifest}" \
      --skills-root "${skills_root}" \
      --target codex)"

  grep -q 'Completed: selected=1, processed=1, target=codex' <<<"${output}" &&
    test -f "${codex_dir}/alpha-required/${marker}" &&
    test ! -f "${codex_dir}/alpha-required/local.txt" &&
    grep -q '\- `notebooklm-shared`' "${PROFILE_DOC}" &&
    grep -q '\- `notebooklm-visual-brief`' "${PROFILE_DOC}" &&
    grep -q '^notebooklm-shared[[:space:]]\+required' "${MANIFEST}" &&
    grep -q '^notebooklm-visual-brief[[:space:]]\+required' "${MANIFEST}"
}

echo "=== sync-notebooklm-skills.sh unit tests ==="
echo ""

assert_ok "required-only" test_required_only
assert_ok "with-optional-and-target-routing" test_with_optional_and_target_routing
assert_ok "dry-run-and-unmanaged-protection" test_dry_run_and_unmanaged_protection
assert_ok "payload-validation" test_payload_validation
assert_ok "managed-replace-and-profile-drift" test_managed_replace_and_profile_manifest_drift

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
