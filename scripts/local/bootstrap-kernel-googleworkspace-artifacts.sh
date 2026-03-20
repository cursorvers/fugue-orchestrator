#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

issue_number=""
issue_title=""
track="readonly-evidence"
cycles="3"
rounds="2"
force="false"
lessons_required="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh [options]

Create execution-ready `.fugue/pre-implement` and `.fugue/implement` artifacts
for the Kernel Google Workspace lane.

Options:
  --issue-number <n>         Required GitHub issue number.
  --issue-title <text>       Optional issue title for context notes.
  --track <id>               One of:
                             readonly-evidence
                             mailbox-readonly
                             bounded-write
                             scope-minimization
                             extension-triage
                             (default: readonly-evidence)
  --cycles <n>               Preflight cycle count to scaffold (default: 3).
  --rounds <n>               Implementation dialogue rounds to scaffold (default: 2).
  --lessons-required         Add an issue-specific section to `lessons.md`.
  --force                    Overwrite existing issue-specific artifacts.
  -h, --help                 Show help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

normalize_track() {
  case "${1:-}" in
    readonly-evidence|mailbox-readonly|bounded-write|scope-minimization|extension-triage)
      printf '%s' "$1"
      ;;
    *)
      fail "invalid --track=$1"
      ;;
  esac
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
    --issue-number)
      issue_number="${2:-}"
      shift 2
      ;;
    --issue-title)
      issue_title="${2:-}"
      shift 2
      ;;
    --track)
      track="$(normalize_track "${2:-}")"
      shift 2
      ;;
    --cycles)
      cycles="$(require_positive_int "${2:-}" "--cycles")"
      shift 2
      ;;
    --rounds)
      rounds="$(require_positive_int "${2:-}" "--rounds")"
      shift 2
      ;;
    --lessons-required)
      lessons_required="true"
      shift
      ;;
    --force)
      force="true"
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

issue_number="$(require_positive_int "${issue_number}" "--issue-number")"

pre_dir="${ROOT_DIR}/.fugue/pre-implement"
impl_dir="${ROOT_DIR}/.fugue/implement"
mkdir -p "${pre_dir}" "${impl_dir}"

todo_report="${pre_dir}/issue-${issue_number}-todo.md"
preflight_report="${pre_dir}/issue-${issue_number}-preflight.md"
research_report="${pre_dir}/issue-${issue_number}-research.md"
plan_report="${pre_dir}/issue-${issue_number}-plan.md"
critic_report="${pre_dir}/issue-${issue_number}-critic.md"
implementation_report="${impl_dir}/issue-${issue_number}-implementation-loop.md"
lessons_report="${pre_dir}/lessons.md"

guard_overwrite() {
  local path="$1"
  if [[ -e "${path}" && "${force}" != "true" ]]; then
    fail "refusing to overwrite existing artifact without --force: ${path#${ROOT_DIR}/}"
  fi
}

for path in \
  "${todo_report}" \
  "${preflight_report}" \
  "${research_report}" \
  "${plan_report}" \
  "${critic_report}" \
  "${implementation_report}"; do
  guard_overwrite "${path}"
done

track_goal() {
  case "${track}" in
    readonly-evidence)
      cat <<'EOF'
Revalidate `meeting-prep` and `standup-report` as bounded readonly evidence for Kernel `preflight enrich`.
EOF
      ;;
    mailbox-readonly)
      cat <<'EOF'
Add mailbox-derived readonly evidence through `weekly-digest` and `gmail-triage` only after Phase 1 is stable.
EOF
      ;;
    bounded-write)
      cat <<'EOF'
Revalidate bounded Workspace write helpers and normalize receipts for operator-approved side effects.
EOF
      ;;
    scope-minimization)
      cat <<'EOF'
Replace broad discovery auth with function-scoped operator auth profiles for the mature Kernel Workspace lane.
EOF
      ;;
    extension-triage)
      cat <<'EOF'
Triage `tasks`, `pubsub`, and `presentations` as explicit extension lanes separate from the core Kernel Workspace path.
EOF
      ;;
  esac
}

track_checklist() {
  case "${track}" in
    readonly-evidence)
      cat <<'EOF'
- [ ] Reconfirm `meeting-prep`
- [ ] Reconfirm `standup-report`
- [ ] Confirm summary-only bounded reinjection
- [ ] Confirm degraded `skipped` / `partial` behavior
- [ ] Confirm service-account readonly path still yields value
- [ ] Record verification evidence and any doc drift
EOF
      ;;
    mailbox-readonly)
      cat <<'EOF'
- [ ] Reconfirm `weekly-digest`
- [ ] Reconfirm `gmail-triage`
- [ ] Confirm mailbox evidence remains summary-only and bounded
- [ ] Confirm user OAuth readonly path is documented separately from Phase 1
- [ ] Record verification evidence and any doc drift
EOF
      ;;
    bounded-write)
      cat <<'EOF'
- [ ] Reconfirm `gmail-send --dry-run`
- [ ] Reconfirm `docs-create`
- [ ] Reconfirm `docs-insert-text`
- [ ] Reconfirm `sheets-append`
- [ ] Reconfirm `drive-upload`
- [ ] Define normalized Workspace write receipt fields
EOF
      ;;
    scope-minimization)
      cat <<'EOF'
- [ ] Document minimum readonly operator auth profile
- [ ] Document mailbox readonly operator auth profile
- [ ] Document minimum bounded-write operator auth profile
- [ ] Separate extension scopes from the mature core profile
- [ ] Remove reliance on `gws auth login --full` from mature-path docs
- [ ] Record migration guidance from recovered March auth state
EOF
      ;;
    extension-triage)
      cat <<'EOF'
- [ ] Decide keep / defer / drop for `tasks`
- [ ] Decide keep / defer / drop for `pubsub`
- [ ] Decide keep / defer / drop for `presentations`
- [ ] Record auth requirements for any kept extension lane
- [ ] Confirm extension work does not block the mature core lane
EOF
      ;;
  esac
}

cat > "${todo_report}" <<EOF
# Issue #${issue_number} TODO

${issue_title:+Title: ${issue_title}}
Track: ${track}

## Plan

1. Confirm the current design and adapter contract for this track.
2. Revalidate the highest-value path with bounded evidence.
3. Capture verification and update docs/tests only where behavior differs.

## Checklist

$(track_checklist)

## Progress

- Bootstrapped from scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh
- Recovered context source: docs/kernel-googleworkspace-resume-plan-2026-03-20.md
- Execution checklist source: docs/kernel-googleworkspace-implementation-todo.md

## Review

- Keep Google Workspace in the adapter plane only.
- Keep summaries bounded; do not promote raw Workspace payloads into control-plane truth.
- Keep extension scope separate from the mature readonly lane unless explicitly required.
EOF

{
  echo "# Issue #${issue_number} Preflight"
  echo
  [[ -n "${issue_title}" ]] && echo "Title: ${issue_title}" && echo
  echo "Track: ${track}"
  echo
  for i in $(seq 1 "${cycles}"); do
    cat <<EOF
## Cycle ${i}
### 1. Plan

### 2. Parallel Simulation

### 3. Critical Review

### 4. Problem Fix

### 5. Replan

EOF
  done
} > "${preflight_report}"

cat > "${research_report}" <<EOF
# Issue #${issue_number} Research

Track: ${track}

## Sources

- docs/kernel-googleworkspace-integration-design.md
- docs/kernel-googleworkspace-resume-plan-2026-03-20.md
- docs/kernel-googleworkspace-implementation-todo.md

## Findings

- $(track_goal)
EOF

cat > "${plan_report}" <<EOF
# Issue #${issue_number} Plan

Track: ${track}

## Proposed Direction

- $(track_goal)

## Constraints

- Keep Workspace bounded to the adapter plane.
- Prefer least privilege for the mature lane.
EOF

cat > "${critic_report}" <<EOF
# Issue #${issue_number} Critical Review

Track: ${track}

## Risks

- Auth scope may be broader than necessary.
- Raw payloads may leak into prompts if evidence envelopes are not enforced.
- Extension work may distract from the mature readonly path.
EOF

{
  echo "# Issue #${issue_number} Implementation Loop"
  echo
  [[ -n "${issue_title}" ]] && echo "Title: ${issue_title}" && echo
  echo "Track: ${track}"
  echo
  for i in $(seq 1 "${rounds}"); do
    cat <<EOF
## Round ${i}
### Implementer Proposal

### Critic Challenge

### Integrator Decision

### Applied Change

### Verification

EOF
  done
} > "${implementation_report}"

if [[ ! -f "${lessons_report}" ]]; then
  cat > "${lessons_report}" <<'EOF'
# Lessons Ledger

EOF
fi

if [[ "${lessons_required}" == "true" ]] && ! grep -Eq "^##[[:space:]]+Issue[[:space:]]+#${issue_number}([[:space:]].*)?$" "${lessons_report}"; then
  {
    echo
    echo "## Issue #${issue_number}"
    echo
    echo "- Mistake pattern:"
    echo "- Preventive rule:"
    echo "- Trigger signal:"
  } >> "${lessons_report}"
fi

printf 'todo=%s\n' "${todo_report#${ROOT_DIR}/}"
printf 'preflight=%s\n' "${preflight_report#${ROOT_DIR}/}"
printf 'research=%s\n' "${research_report#${ROOT_DIR}/}"
printf 'plan=%s\n' "${plan_report#${ROOT_DIR}/}"
printf 'critic=%s\n' "${critic_report#${ROOT_DIR}/}"
printf 'implementation=%s\n' "${implementation_report#${ROOT_DIR}/}"
printf 'lessons=%s\n' "${lessons_report#${ROOT_DIR}/}"
