#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/.fugue/kernel-googleworkspace-workset"
START_ISSUE_NUMBER="9101"
FORCE="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/bootstrap-kernel-googleworkspace-workset.sh [options]

Prepare a local-first Kernel Google Workspace workset without requiring GitHub
issue creation or live user re-authentication.

This script:
- fixes the current goal into a local workset
- renders issue packets for Issues 1-5
- bootstraps `.fugue/pre-implement` and `.fugue/implement` artifacts for each
  track using synthetic local issue numbers

Options:
  --out-dir <path>            Output directory for issue packets and manifest
                              (default: .fugue/kernel-googleworkspace-workset)
  --start-issue-number <n>    Synthetic local issue number base (default: 9101)
  --force                     Overwrite existing workset and issue artifacts
  -h, --help                  Show help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_positive_int() {
  local raw="${1:-}"
  local label="${2:-value}"
  [[ "${raw}" =~ ^[0-9]+$ ]] || fail "${label} must be a positive integer"
  (( raw > 0 )) || fail "${label} must be greater than zero"
  printf '%s' "${raw}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --start-issue-number)
      START_ISSUE_NUMBER="$(require_positive_int "${2:-}" "--start-issue-number")"
      shift 2
      ;;
    --force)
      FORCE="true"
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

extract_title() {
  local file="$1"
  awk '
    found && /^`/ { gsub(/^`|`$/, ""); print; exit }
    /^## Suggested Title$/ { found=1 }
  ' "${file}"
}

extract_body() {
  local file="$1"
  awk '
    /^## Paste-Ready Body$/ { in_section=1; next }
    in_section && /^```md$/ { capture=1; next }
    capture && /^```$/ { exit }
    capture { print }
  ' "${file}"
}

mkdir -p "${OUT_DIR}"

if [[ "${FORCE}" != "true" && -e "${OUT_DIR}/manifest.tsv" ]]; then
  fail "workset already exists at ${OUT_DIR}; rerun with --force to overwrite"
fi

ready_docs=(
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-1-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-2-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-3-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-4-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-5-ready.md"
)
tracks=(
  "readonly-evidence"
  "mailbox-readonly"
  "bounded-write"
  "scope-minimization"
  "extension-triage"
)

for file in "${ready_docs[@]}"; do
  [[ -f "${file}" ]] || fail "missing ready doc: ${file#${ROOT_DIR}/}"
done

issues_dir="${OUT_DIR}/issues"
mkdir -p "${issues_dir}"

manifest_file="${OUT_DIR}/manifest.tsv"
printf 'local_issue_number	track	title	issue_packet\n' > "${manifest_file}"

for idx in "${!ready_docs[@]}"; do
  local_issue_number=$((START_ISSUE_NUMBER + idx))
  track="${tracks[${idx}]}"
  ready_doc="${ready_docs[${idx}]}"
  title="$(extract_title "${ready_doc}")"
  body="$(extract_body "${ready_doc}")"
  [[ -n "${title}" ]] || fail "could not extract title from ${ready_doc#${ROOT_DIR}/}"
  [[ -n "${body}" ]] || fail "could not extract body from ${ready_doc#${ROOT_DIR}/}"

  packet_file="${issues_dir}/issue-$((idx + 1)).md"
  cat > "${packet_file}" <<EOF
# ${title}

Local synthetic issue number: ${local_issue_number}
Track: ${track}

${body}
EOF

  bootstrap_cmd=(
    bash
    "${ROOT_DIR}/scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh"
    --issue-number "${local_issue_number}"
    --track "${track}"
  )
  if [[ "${FORCE}" == "true" ]]; then
    bootstrap_cmd+=(--force)
  fi
  (cd "${ROOT_DIR}" && "${bootstrap_cmd[@]}" >/dev/null)

  printf '%s	%s	%s	%s\n' \
    "${local_issue_number}" \
    "${track}" \
    "${title}" \
    "${packet_file#${ROOT_DIR}/}" >> "${manifest_file}"
done

cat > "${OUT_DIR}/README.md" <<EOF
# Kernel Google Workspace Workset

Goal source:

- docs/kernel-googleworkspace-goal-2026-03-20.md

Primary Phase 1 goal:

- make meeting-prep and standup-report reliable readonly evidence sources for
  Kernel preflight enrich

This workset is local-first and does not require GitHub issue creation.

Included tracks:

1. readonly-evidence
2. mailbox-readonly
3. bounded-write
4. scope-minimization
5. extension-triage

Issue packet index:

- see manifest.tsv

Execution start point:

- use .fugue/pre-implement/issue-${START_ISSUE_NUMBER}-todo.md for Phase 1
EOF

printf 'workset=%s\n' "${OUT_DIR#${ROOT_DIR}/}"
printf 'manifest=%s\n' "${manifest_file#${ROOT_DIR}/}"
