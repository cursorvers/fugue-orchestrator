#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MANIFEST="${REPO_ROOT}/config/skills/notebooklm-cli-baseline.tsv"
SKILLS_ROOT="${NOTEBOOKLM_SKILLS_ROOT:-${REPO_ROOT}/skills}"

TARGET="both"            # codex | claude | both
INCLUDE_OPTIONAL="false" # true | false
FORCE="false"            # true | false
DRY_RUN="false"          # true | false

CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-${HOME}/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${HOME}/.claude/skills}"
MANAGED_MARKER=".fugue-managed-notebooklm"

usage() {
  cat <<'EOF'
Usage:
  scripts/skills/sync-notebooklm-skills.sh [options]

Options:
  --target <codex|claude|both>    Install destination. Default: both
  --with-optional                 Include optional skills from manifest.
  --manifest <path>               Manifest file path override.
  --skills-root <path>            Skill payload root override.
  --force                         Replace existing non-managed target directories.
  --dry-run                       Print actions without writing files.
  -h, --help                      Show this help.

Environment:
  NOTEBOOKLM_SKILLS_ROOT          Local skill payload root (default: repo skills/)
  CODEX_SKILLS_DIR                Codex skills directory (default: ~/.codex/skills)
  CLAUDE_SKILLS_DIR               Claude skills directory (default: ~/.claude/skills)
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        [[ $# -ge 2 ]] || fail "--target requires a value"
        TARGET="$2"
        shift 2
        ;;
      --with-optional)
        INCLUDE_OPTIONAL="true"
        shift
        ;;
      --manifest)
        [[ $# -ge 2 ]] || fail "--manifest requires a value"
        MANIFEST="$2"
        shift 2
        ;;
      --skills-root)
        [[ $# -ge 2 ]] || fail "--skills-root requires a value"
        SKILLS_ROOT="$2"
        shift 2
        ;;
      --force)
        FORCE="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
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

  case "${TARGET}" in
    codex|claude|both) ;;
    *)
      fail "--target must be codex, claude, or both"
      ;;
  esac
}

validate_skill_payload() {
  local skill_dir="$1"
  local skill_name="$2"
  local skill_md="${skill_dir}/SKILL.md"

  [[ -d "${skill_dir}" ]] || fail "skill not found: ${skill_name}"
  [[ -f "${skill_md}" ]] || fail "skill ${skill_name} has no SKILL.md"

  head -n1 "${skill_md}" | grep -q '^---$' || fail "skill ${skill_name} frontmatter is missing"
  grep -q '^name:' "${skill_md}" || fail "skill ${skill_name} has no name in frontmatter"
  grep -q '^description:' "${skill_md}" || fail "skill ${skill_name} has no description in frontmatter"

  if rg -n --no-messages --fixed-strings -- '--yolo' "${skill_md}" >/dev/null; then
    fail "skill ${skill_name} includes --yolo guidance; blocked by security policy"
  fi
  if rg -n --no-messages --fixed-strings -- '--full-auto' "${skill_md}" >/dev/null; then
    fail "skill ${skill_name} includes --full-auto guidance; blocked by security policy"
  fi
}

copy_skill() {
  local source_dir="$1"
  local target_base="$2"
  local skill_name="$3"
  local target_dir="${target_base}/${skill_name}"

  [[ -n "${target_base}" && "${target_base}" != "/" ]] || fail "unsafe target_base: ${target_base}"
  mkdir -p "${target_base}"

  if [[ -d "${target_dir}" ]]; then
    if [[ -f "${target_dir}/${MANAGED_MARKER}" || "${FORCE}" == "true" ]]; then
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY-RUN replace ${target_dir}"
      else
        rm -rf "${target_dir}"
      fi
    else
      echo "SKIP ${target_dir} (exists and not managed, use --force to replace)"
      return 0
    fi
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN install ${skill_name} -> ${target_dir}"
    return 0
  fi

  mkdir -p "${target_dir}"
  cp -R "${source_dir}/." "${target_dir}/"
  cat > "${target_dir}/${MANAGED_MARKER}" <<EOF
source_repo=fugue-orchestrator
source_root=${SKILLS_ROOT}
installed_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

read_manifest() {
  [[ -f "${MANIFEST}" ]] || fail "manifest not found: ${MANIFEST}"
  awk -F'\t' '
    BEGIN { OFS="\t" }
    /^#/ { next }
    NF < 2 { next }
    { print $1, $2 }
  ' "${MANIFEST}"
}

main() {
  parse_args "$@"
  require_cmd awk
  require_cmd rg

  local installed=0 selected=0
  while IFS=$'\t' read -r skill_name profile; do
    [[ -n "${skill_name}" ]] || continue

    if [[ "${profile}" == "optional" && "${INCLUDE_OPTIONAL}" != "true" ]]; then
      continue
    fi

    selected=$((selected + 1))
    local source_skill_dir="${SKILLS_ROOT}/${skill_name}"
    validate_skill_payload "${source_skill_dir}" "${skill_name}"

    if [[ "${TARGET}" == "codex" || "${TARGET}" == "both" ]]; then
      copy_skill "${source_skill_dir}" "${CODEX_SKILLS_DIR}" "${skill_name}"
    fi
    if [[ "${TARGET}" == "claude" || "${TARGET}" == "both" ]]; then
      copy_skill "${source_skill_dir}" "${CLAUDE_SKILLS_DIR}" "${skill_name}"
    fi
    installed=$((installed + 1))
  done < <(read_manifest)

  echo "Completed: selected=${selected}, processed=${installed}, target=${TARGET}, optional=${INCLUDE_OPTIONAL}, dry_run=${DRY_RUN}"
  echo "Source: ${SKILLS_ROOT}"
}

main "$@"
