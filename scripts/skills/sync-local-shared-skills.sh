#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MANIFEST="${REPO_ROOT}/config/skills/local-shared-baseline.tsv"
SOURCE_BASE="${REPO_ROOT}/local-shared-skills"

TARGET="both"            # codex | claude | both
INCLUDE_OPTIONAL="false" # true | false
FORCE="false"            # true | false
DRY_RUN="false"          # true | false

CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-${HOME}/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${HOME}/.claude/skills}"
MANAGED_MARKER=".fugue-managed-local-shared"
CLAUDE_SOURCE_ROOT="${REPO_ROOT}/claude-config/assets/skills"

usage() {
  cat <<'EOF'
Usage:
  scripts/skills/sync-local-shared-skills.sh [options]

Options:
  --target <codex|claude|both>    Install destination. Default: both
  --with-optional                 Include optional skills from manifest.
  --manifest <path>               Manifest file path override.
  --force                         Replace existing non-managed target directories.
  --dry-run                       Print actions without writing files.
  -h, --help                      Show this help.

Environment:
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

  [[ -f "${skill_md}" ]] || fail "skill ${skill_name} has no SKILL.md"
  head -n1 "${skill_md}" | grep -q '^---$' || fail "skill ${skill_name} frontmatter is missing"
  grep -q '^name:' "${skill_md}" || fail "skill ${skill_name} has no name in frontmatter"
  grep -q '^description:' "${skill_md}" || fail "skill ${skill_name} has no description in frontmatter"
}

copy_skill() {
  local source_dir="$1"
  local target_base="$2"
  local skill_name="$3"
  local target_dir="${target_base}/${skill_name}"
  local source_real
  local target_real

  source_real="$(cd "${source_dir}" && pwd -P)"

  mkdir -p "${target_base}"

  if [[ -d "${target_dir}" ]]; then
    target_real="$(cd "${target_dir}" && pwd -P)"
    if [[ "${source_real}" == "${target_real}" ]]; then
      echo "SKIP ${target_dir} (already points at ${source_real})"
      return 0
    fi
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
source_repo=${REPO_ROOT}
source_base=${SOURCE_BASE}
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

is_within_dir() {
  local maybe_path="$1"
  local expected_dir="$2"
  local actual_real expected_real
  [[ -e "${maybe_path}" ]] || return 1
  [[ -d "${maybe_path}" ]] || return 1
  actual_real="$(cd "${maybe_path}" && pwd -P)"
  expected_real="$(cd "${expected_dir}" && pwd -P)"
  [[ "${actual_real}" == "${expected_real}" || "${actual_real}" == "${expected_real}"/* ]]
}

main() {
  parse_args "$@"
  require_cmd awk
  require_cmd cp
  require_cmd grep
  require_cmd head
  require_cmd rm

  local sync_codex="false" sync_claude="false"
  if [[ "${TARGET}" == "codex" || "${TARGET}" == "both" ]]; then
    sync_codex="true"
  fi
  if [[ "${TARGET}" == "claude" || "${TARGET}" == "both" ]]; then
    sync_claude="true"
  fi

  if [[ "${sync_claude}" == "true" ]] && is_within_dir "${CLAUDE_SKILLS_DIR}" "${CLAUDE_SOURCE_ROOT}"; then
    echo "SKIP claude target (${CLAUDE_SKILLS_DIR} resolves inside ${CLAUDE_SOURCE_ROOT}; manage Claude-side adapters in source tree)"
    sync_claude="false"
  fi

  local installed=0 selected=0
  while IFS=$'\t' read -r skill_name profile; do
    [[ -n "${skill_name}" ]] || continue

    if [[ "${profile}" == "optional" && "${INCLUDE_OPTIONAL}" != "true" ]]; then
      continue
    fi

    selected=$((selected + 1))
    local source_skill_dir="${SOURCE_BASE}/${skill_name}"
    [[ -d "${source_skill_dir}" ]] || fail "local shared skill not found: ${skill_name}"
    validate_skill_payload "${source_skill_dir}" "${skill_name}"

    if [[ "${sync_codex}" == "true" ]]; then
      copy_skill "${source_skill_dir}" "${CODEX_SKILLS_DIR}" "${skill_name}"
    fi
    if [[ "${sync_claude}" == "true" ]]; then
      copy_skill "${source_skill_dir}" "${CLAUDE_SKILLS_DIR}" "${skill_name}"
    fi
    installed=$((installed + 1))
  done < <(read_manifest)

  echo "local shared skills processed: ${installed} (selected=${selected}, target=${TARGET}, dry_run=${DRY_RUN})"
}

main "$@"
