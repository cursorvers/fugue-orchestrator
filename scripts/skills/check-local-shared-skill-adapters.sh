#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MANIFEST="${REPO_ROOT}/config/skills/local-shared-baseline.tsv"
SOURCE_BASE="${REPO_ROOT}/local-shared-skills"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-${HOME}/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${HOME}/.claude/skills}"
CLAUDE_SOURCE_SKILLS_DIR="${CLAUDE_SOURCE_SKILLS_DIR:-${REPO_ROOT}/claude-config/assets/skills}"

CHECK_RUNTIME="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/skills/check-local-shared-skill-adapters.sh [--runtime]

Checks:
  - every manifest-selected local shared skill has SKILL.md and CLAUDE.md
  - no top-level local-shared skill with SKILL.md is outside the manifest
  - x-auto authority docs must not include hardcoded /Users/.../Dev/x-auto paths
  - optional --runtime requires runtime/source-tree SKILL.md + CLAUDE.md and CLAUDE.md parity
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local literal="$2"
  local label="$3"
  if ! grep -F -q -- "${literal}" "${file}"; then
    echo "missing ${label}: ${file}" >&2
    errors=$((errors + 1))
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      CHECK_RUNTIME="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -f "${MANIFEST}" ]] || fail "manifest not found: ${MANIFEST}"

selected_manifest_skills() {
  awk -F'\t' '
    /^#/ { next }
    NF < 2 { next }
    $2 == "optional" { next }
    { print $1 }
  ' "${MANIFEST}"
}

all_manifest_skills() {
  awk -F'\t' '
    /^#/ { next }
    NF < 2 { next }
    { print $1 }
  ' "${MANIFEST}"
}

is_manifest_skill() {
  local candidate="$1"
  local skill
  while IFS= read -r skill; do
    [[ "${skill}" == "${candidate}" ]] && return 0
  done < <(all_manifest_skills)
  return 1
}

errors=0

if grep -R -n -E '/Users/[^[:space:]]+/Dev/x-auto' "${SOURCE_BASE}/x-auto" "${CLAUDE_SOURCE_SKILLS_DIR}/x-auto" 2>/dev/null; then
  echo "hardcoded user-specific x-auto authority path found" >&2
  errors=$((errors + 1))
fi

for x_auto_contract_file in \
  "${SOURCE_BASE}/x-auto/SKILL.md" \
  "${SOURCE_BASE}/x-auto/CLAUDE.md" \
  "${CLAUDE_SOURCE_SKILLS_DIR}/x-auto/SKILL.md" \
  "${CLAUDE_SOURCE_SKILLS_DIR}/x-auto/CLAUDE.md"
do
  [[ -f "${x_auto_contract_file}" ]] || continue
  require_literal "${x_auto_contract_file}" 'x-auto/CLAUDE.md' 'x-auto workspace authority reference'
  require_literal "${x_auto_contract_file}" './CLAUDE.md' 'x-auto runtime-root authority reference'
  require_literal "${x_auto_contract_file}" 'FUGUE_DEV_ROOT' 'x-auto FUGUE_DEV_ROOT fallback contract'
done

while IFS= read -r skill; do
  skill_dir="${SOURCE_BASE}/${skill}"
  if [[ ! -f "${skill_dir}/SKILL.md" ]]; then
    echo "missing SKILL.md: ${skill_dir}" >&2
    errors=$((errors + 1))
  fi
  if [[ ! -f "${skill_dir}/CLAUDE.md" ]]; then
    echo "missing CLAUDE.md: ${skill_dir}" >&2
    errors=$((errors + 1))
  fi

  if [[ "${CHECK_RUNTIME}" == "true" && -f "${skill_dir}/CLAUDE.md" ]]; then
    for target_base in "${CODEX_SKILLS_DIR}" "${CLAUDE_SKILLS_DIR}" "${CLAUDE_SOURCE_SKILLS_DIR}"; do
      target_dir="${target_base}/${skill}"
      target_skill="${target_base}/${skill}/SKILL.md"
      target="${target_base}/${skill}/CLAUDE.md"
      if [[ -L "${target_dir}" ]]; then
        echo "runtime skill dir must be a managed real directory, not a symlink: ${target_dir}" >&2
        errors=$((errors + 1))
      fi
      if [[ ! -f "${target_skill}" ]]; then
        echo "runtime SKILL.md missing: ${target_skill}" >&2
        errors=$((errors + 1))
      fi
      if [[ ! -f "${target}" ]]; then
        echo "runtime CLAUDE.md missing: ${target}" >&2
        errors=$((errors + 1))
      elif ! cmp -s "${skill_dir}/CLAUDE.md" "${target}"; then
        echo "runtime CLAUDE.md differs: ${target}" >&2
        errors=$((errors + 1))
      fi
    done
  fi
done < <(selected_manifest_skills)

for skill_dir in "${SOURCE_BASE}"/*; do
  [[ -d "${skill_dir}" ]] || continue
  skill="$(basename "${skill_dir}")"
  [[ -f "${skill_dir}/SKILL.md" ]] || continue
  if ! is_manifest_skill "${skill}"; then
    echo "top-level local-shared skill not in manifest: ${skill_dir}" >&2
    errors=$((errors + 1))
  fi
done

if [[ "${errors}" -gt 0 ]]; then
  fail "local shared skill adapter check failed (${errors} issue(s))"
fi

echo "local shared skill adapters ok"
