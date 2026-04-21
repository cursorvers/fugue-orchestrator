#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/scripts/skills" "${TMP_DIR}/config/skills" "${TMP_DIR}/local-shared-skills"
cp "${REPO_ROOT}/scripts/skills/sync-local-shared-skills.sh" "${TMP_DIR}/scripts/skills/"
cp "${REPO_ROOT}/scripts/skills/check-local-shared-skill-adapters.sh" "${TMP_DIR}/scripts/skills/"

cat > "${TMP_DIR}/config/skills/local-shared-baseline.tsv" <<'TSV'
demo	required
x-auto	required
optional-demo	optional
TSV

mkdir -p "${TMP_DIR}/local-shared-skills/demo"
cat > "${TMP_DIR}/local-shared-skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: Test skill.
---
# Demo
EOF
cat > "${TMP_DIR}/local-shared-skills/demo/CLAUDE.md" <<'EOF'
# demo スキルアダプター（薄型）
EOF
mkdir -p "${TMP_DIR}/local-shared-skills/optional-demo"
cat > "${TMP_DIR}/local-shared-skills/optional-demo/SKILL.md" <<'EOF'
---
name: optional-demo
description: Optional test skill.
---
# Optional Demo
EOF
cat > "${TMP_DIR}/local-shared-skills/optional-demo/CLAUDE.md" <<'EOF'
# optional demo スキルアダプター（薄型）
EOF
mkdir -p "${TMP_DIR}/local-shared-skills/x-auto" "${TMP_DIR}/claude-config/assets/skills/x-auto"
cat > "${TMP_DIR}/local-shared-skills/x-auto/SKILL.md" <<'EOF'
---
name: x-auto
description: Test x-auto.
---
# x-auto

Read ./CLAUDE.md when in the x-auto runtime root. Otherwise read x-auto/CLAUDE.md first. If it is unavailable, use FUGUE_DEV_ROOT as the only fallback.
EOF
cat > "${TMP_DIR}/local-shared-skills/x-auto/CLAUDE.md" <<'EOF'
# x-auto スキルアダプター（薄型）

Read ./CLAUDE.md when in the x-auto runtime root. Otherwise read x-auto/CLAUDE.md first. If it is unavailable, use FUGUE_DEV_ROOT as the only fallback.
EOF
cat > "${TMP_DIR}/claude-config/assets/skills/x-auto/SKILL.md" <<'EOF'
---
name: x-auto
description: Test x-auto source.
---
# x-auto

Read ./CLAUDE.md when in the x-auto runtime root. Otherwise read x-auto/CLAUDE.md first. If it is unavailable, use FUGUE_DEV_ROOT as the only fallback.
EOF
cat > "${TMP_DIR}/claude-config/assets/skills/x-auto/CLAUDE.md" <<'EOF'
# x-auto source adapter

Read ./CLAUDE.md when in the x-auto runtime root. Otherwise read x-auto/CLAUDE.md first. If it is unavailable, use FUGUE_DEV_ROOT as the only fallback.
EOF

bash "${TMP_DIR}/scripts/skills/check-local-shared-skill-adapters.sh"
bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target codex --dry-run >"${TMP_DIR}/sync-optional.out" 2>"${TMP_DIR}/sync-optional.err"

echo '/Users/example/Dev/x-auto/CLAUDE.md' >> "${TMP_DIR}/local-shared-skills/x-auto/SKILL.md"
if bash "${TMP_DIR}/scripts/skills/check-local-shared-skill-adapters.sh" >"${TMP_DIR}/hardcoded-path.out" 2>"${TMP_DIR}/hardcoded-path.err"; then
  echo "expected hardcoded x-auto authority path check to fail" >&2
  exit 1
fi
cat > "${TMP_DIR}/local-shared-skills/x-auto/SKILL.md" <<'EOF'
---
name: x-auto
description: Test x-auto.
---
# x-auto

Read ./CLAUDE.md when in the x-auto runtime root. Otherwise read x-auto/CLAUDE.md first. If it is unavailable, use FUGUE_DEV_ROOT as the only fallback.
EOF

rm "${TMP_DIR}/local-shared-skills/demo/CLAUDE.md"
if bash "${TMP_DIR}/scripts/skills/check-local-shared-skill-adapters.sh" >"${TMP_DIR}/check-missing.out" 2>"${TMP_DIR}/check-missing.err"; then
  echo "expected missing CLAUDE.md check to fail" >&2
  exit 1
fi
cat > "${TMP_DIR}/local-shared-skills/demo/CLAUDE.md" <<'EOF'
# demo スキルアダプター（薄型）
EOF

mkdir -p "${TMP_DIR}/local-shared-skills/demo.backup-20260419"
cat > "${TMP_DIR}/local-shared-skills/demo.backup-20260419/SKILL.md" <<'EOF'
---
name: demo-backup
description: Should not be active.
---
# Backup
EOF
cat > "${TMP_DIR}/local-shared-skills/demo.backup-20260419/CLAUDE.md" <<'EOF'
# backup
EOF
if bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target codex --dry-run >"${TMP_DIR}/sync-backup.out" 2>"${TMP_DIR}/sync-backup.err"; then
  echo "expected backup-like source tree check to fail" >&2
  exit 1
fi
rm -rf "${TMP_DIR}/local-shared-skills/demo.backup-20260419"

CODEX_DIR="${TMP_DIR}/codex-skills"
CLAUDE_DIR="${TMP_DIR}/claude-skills"
CLAUDE_SOURCE_DIR="${TMP_DIR}/claude-source-skills"
mkdir -p "${CODEX_DIR}/old-skill"
cat > "${CODEX_DIR}/old-skill/.fugue-managed-local-shared" <<'EOF'
source_repo=test
EOF

CODEX_SKILLS_DIR="${CODEX_DIR}" bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target codex --prune-stale --dry-run
[[ -d "${CODEX_DIR}/old-skill" ]] || {
  echo "dry-run prune removed stale skill" >&2
  exit 1
}

CODEX_SKILLS_DIR="${CODEX_DIR}" bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target codex --prune-stale
[[ ! -d "${CODEX_DIR}/old-skill" ]] || {
  echo "stale managed skill was not pruned" >&2
  exit 1
}
[[ -f "${CODEX_DIR}/demo/CLAUDE.md" ]] || {
  echo "demo skill was not installed" >&2
  exit 1
}

if CODEX_SKILLS_DIR="${CODEX_DIR}" CLAUDE_SKILLS_DIR="${CLAUDE_DIR}" CLAUDE_SOURCE_SKILLS_DIR="${CLAUDE_SOURCE_DIR}" bash "${TMP_DIR}/scripts/skills/check-local-shared-skill-adapters.sh" --runtime >"${TMP_DIR}/runtime-missing.out" 2>"${TMP_DIR}/runtime-missing.err"; then
  echo "expected runtime check to fail when runtime/source CLAUDE.md is missing" >&2
  exit 1
fi

mkdir -p "${CLAUDE_DIR}/demo" "${CLAUDE_DIR}/x-auto" "${CLAUDE_SOURCE_DIR}/demo" "${CLAUDE_SOURCE_DIR}/x-auto"
cat > "${CLAUDE_DIR}/demo/keep.txt" <<'EOF'
preserve me
EOF
cat > "${CLAUDE_DIR}/demo/SKILL.md" <<'EOF'
---
name: demo
description: Existing runtime skill.
---
# Demo Runtime
EOF
cat > "${CLAUDE_DIR}/demo/CLAUDE.md" <<'EOF'
# stale
EOF
cp "${TMP_DIR}/local-shared-skills/demo/SKILL.md" "${CLAUDE_SOURCE_DIR}/demo/SKILL.md"
cp "${TMP_DIR}/local-shared-skills/demo/CLAUDE.md" "${CLAUDE_SOURCE_DIR}/demo/CLAUDE.md"
cp "${TMP_DIR}/local-shared-skills/x-auto/SKILL.md" "${CLAUDE_DIR}/x-auto/SKILL.md"
cp "${TMP_DIR}/local-shared-skills/x-auto/CLAUDE.md" "${CLAUDE_DIR}/x-auto/CLAUDE.md"
cp "${TMP_DIR}/local-shared-skills/x-auto/SKILL.md" "${CLAUDE_SOURCE_DIR}/x-auto/SKILL.md"
cp "${TMP_DIR}/local-shared-skills/x-auto/CLAUDE.md" "${CLAUDE_SOURCE_DIR}/x-auto/CLAUDE.md"

CLAUDE_BAD_DIR="${TMP_DIR}/claude-bad-skills"
mkdir -p "${CLAUDE_BAD_DIR}/demo"
cat > "${CLAUDE_BAD_DIR}/demo/CLAUDE.md" <<'EOF'
# stale
EOF
if CODEX_SKILLS_DIR="${CODEX_DIR}" CLAUDE_SKILLS_DIR="${CLAUDE_BAD_DIR}" bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target claude --adapter-only >"${TMP_DIR}/adapter-missing-skill.out" 2>"${TMP_DIR}/adapter-missing-skill.err"; then
  echo "expected adapter-only to fail when target SKILL.md is missing" >&2
  exit 1
fi

CLAUDE_EMPTY_DIR="${TMP_DIR}/claude-empty-skills"
if CODEX_SKILLS_DIR="${CODEX_DIR}" CLAUDE_SKILLS_DIR="${CLAUDE_EMPTY_DIR}" bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target claude --adapter-only >"${TMP_DIR}/adapter-missing-dir.out" 2>"${TMP_DIR}/adapter-missing-dir.err"; then
  echo "expected adapter-only to fail when target skill directory is missing" >&2
  exit 1
fi

CODEX_SKILLS_DIR="${CODEX_DIR}" CLAUDE_SKILLS_DIR="${CLAUDE_DIR}" bash "${TMP_DIR}/scripts/skills/sync-local-shared-skills.sh" --target claude --adapter-only
cmp -s "${TMP_DIR}/local-shared-skills/demo/CLAUDE.md" "${CLAUDE_DIR}/demo/CLAUDE.md" || {
  echo "adapter-only did not sync CLAUDE.md" >&2
  exit 1
}
[[ -f "${CLAUDE_DIR}/demo/keep.txt" ]] || {
  echo "adapter-only removed existing Claude skill assets" >&2
  exit 1
}

CODEX_SKILLS_DIR="${CODEX_DIR}" CLAUDE_SKILLS_DIR="${CLAUDE_DIR}" CLAUDE_SOURCE_SKILLS_DIR="${CLAUDE_SOURCE_DIR}" bash "${TMP_DIR}/scripts/skills/check-local-shared-skill-adapters.sh" --runtime

echo "local shared skill adapter tests ok"
