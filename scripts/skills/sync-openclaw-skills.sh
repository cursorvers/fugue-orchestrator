#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MANIFEST="${REPO_ROOT}/config/skills/fugue-openclaw-baseline.tsv"
OPENCLAW_REF_DEFAULT="59c78c105a772d7015718a5207c022c3d4fe875d"
OPENCLAW_REPO="${OPENCLAW_REPO:-openclaw/openclaw}"
OPENCLAW_REF="${OPENCLAW_REF:-${OPENCLAW_REF_DEFAULT}}"

TARGET="both"            # codex | claude | both
INCLUDE_OPTIONAL="false" # true | false
FORCE="false"            # true | false
DRY_RUN="false"          # true | false

CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-${HOME}/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${HOME}/.claude/skills}"
MANAGED_MARKER=".fugue-managed-openclaw"
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/skills/sync-openclaw-skills.sh [options]

Options:
  --target <codex|claude|both>    Install destination. Default: both
  --with-optional                 Include optional skills from manifest.
  --ref <git-ref>                 Pin OpenClaw source ref. Default is pinned SHA.
  --manifest <path>               Manifest file path override.
  --force                         Replace existing non-managed target directories.
  --dry-run                       Print actions without writing files.
  -h, --help                      Show this help.

Environment:
  OPENCLAW_REPO                   GitHub repository (default: openclaw/openclaw)
  OPENCLAW_REF                    Source ref override (tag/branch/sha)
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
      --ref)
        [[ $# -ge 2 ]] || fail "--ref requires a value"
        OPENCLAW_REF="$2"
        shift 2
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

download_openclaw_snapshot() {
  local tmp_dir="$1"
  local tarball="${tmp_dir}/openclaw.tar.gz"
  local url="https://codeload.github.com/${OPENCLAW_REPO}/tar.gz/${OPENCLAW_REF}"

  echo "Downloading ${OPENCLAW_REPO}@${OPENCLAW_REF}"
  curl -fsSL "${url}" -o "${tarball}"
  tar -xzf "${tarball}" -C "${tmp_dir}"
}

resolve_snapshot_root() {
  local tmp_dir="$1"
  local root
  root="$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name 'openclaw-*' | head -n1 || true)"
  [[ -n "${root}" ]] || fail "could not find extracted openclaw directory"
  echo "${root}"
}

validate_skill_payload() {
  local skill_dir="$1"
  local skill_name="$2"
  local skill_md="${skill_dir}/SKILL.md"

  [[ -f "${skill_md}" ]] || fail "skill ${skill_name} has no SKILL.md"

  # Reject malformed frontmatter to avoid installing incompatible entries.
  head -n1 "${skill_md}" | grep -q '^---$' || fail "skill ${skill_name} frontmatter is missing"
  grep -q '^name:' "${skill_md}" || fail "skill ${skill_name} has no name in frontmatter"
  grep -q '^description:' "${skill_md}" || fail "skill ${skill_name} has no description in frontmatter"

  # Guard against importing clearly unsafe auto-execution patterns.
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
  local target_dir="${target_base}/openclaw-${skill_name}"

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
source_repo=${OPENCLAW_REPO}
source_ref=${OPENCLAW_REF}
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
  require_cmd curl
  require_cmd tar
  require_cmd awk
  require_cmd rg

  local snapshot_root
  TMP_DIR="$(mktemp -d)"
  trap 'if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]]; then rm -rf "${TMP_DIR}"; fi' EXIT

  download_openclaw_snapshot "${TMP_DIR}"
  snapshot_root="$(resolve_snapshot_root "${TMP_DIR}")"

  local installed=0 selected=0
  while IFS=$'\t' read -r skill_name profile; do
    [[ -n "${skill_name}" ]] || continue

    if [[ "${profile}" == "optional" && "${INCLUDE_OPTIONAL}" != "true" ]]; then
      continue
    fi

    selected=$((selected + 1))
    local source_skill_dir="${snapshot_root}/skills/${skill_name}"
    [[ -d "${source_skill_dir}" ]] || fail "skill not found in snapshot: ${skill_name}"
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
  echo "Source: ${OPENCLAW_REPO}@${OPENCLAW_REF}"
}

main "$@"
