#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/notebooklm-bin.sh
source "${ROOT_DIR}/scripts/lib/notebooklm-bin.sh"

ADAPTER_SCRIPT="${NOTEBOOKLM_READINESS_ADAPTER_SCRIPT:-${ROOT_DIR}/scripts/lib/notebooklm-cli-adapter.sh}"
SYNC_SCRIPT="${NOTEBOOKLM_READINESS_SYNC_SCRIPT:-${ROOT_DIR}/scripts/skills/sync-notebooklm-skills.sh}"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-${HOME}/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-${HOME}/.claude/skills}"
LIVE_SMOKE_MODE="$(printf '%s' "${NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE:-off}" | tr '[:upper:]' '[:lower:]')"
EXECUTE_LIVE_MODE="$(printf '%s' "${NOTEBOOKLM_READINESS_EXECUTE_LIVE_MODE:-off}" | tr '[:upper:]' '[:lower:]')"
REQUIRE_OPTIONAL="$(printf '%s' "${NOTEBOOKLM_READINESS_REQUIRE_OPTIONAL:-false}" | tr '[:upper:]' '[:lower:]')"
SKIP_REPO_TESTS="$(printf '%s' "${NOTEBOOKLM_READINESS_SKIP_REPO_TESTS:-false}" | tr '[:upper:]' '[:lower:]')"
NLM_BIN_REQUESTED="${NOTEBOOKLM_READINESS_NLM_BIN:-${NLM_BIN:-${FUGUE_NOTEBOOKLM_BIN:-nlm}}}"
NLM_BIN=""

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_repo_test() {
  local rel="$1"
  echo "==> repo test: ${rel}"
  bash "${ROOT_DIR}/${rel}"
}

check_skill_dir() {
  local base="$1"
  local skill="$2"
  local path="${base}/${skill}"
  [[ -d "${path}" ]] || fail "missing installed skill: ${path}"
  [[ -f "${path}/SKILL.md" ]] || fail "missing SKILL.md for ${path}"
}

check_installed_skills() {
  echo "==> installed skills"
  check_skill_dir "${CODEX_SKILLS_DIR}" "notebooklm-shared"
  check_skill_dir "${CODEX_SKILLS_DIR}" "notebooklm-visual-brief"
  check_skill_dir "${CLAUDE_SKILLS_DIR}" "notebooklm-shared"
  check_skill_dir "${CLAUDE_SKILLS_DIR}" "notebooklm-visual-brief"
  if [[ "${REQUIRE_OPTIONAL}" == "true" ]]; then
    check_skill_dir "${CODEX_SKILLS_DIR}" "notebooklm-slide-prep"
    check_skill_dir "${CLAUDE_SKILLS_DIR}" "notebooklm-slide-prep"
  fi
}

run_live_smoke() {
  local note_file manifest run_dir output smoke_tmp
  smoke_tmp="$(mktemp -d "${TMPDIR:-/tmp}/notebooklm-readiness.XXXXXX")"
  note_file="${smoke_tmp}/source.md"
  manifest="${smoke_tmp}/source-manifest.json"
  run_dir="${smoke_tmp}/run"

  printf '# readiness smoke\n' > "${note_file}"
  jq -cn --arg value "${note_file}" '{sources:[{type:"file", value:$value, wait:true}]}' > "${manifest}"

  echo "==> live smoke: adapter smoke"
  output="$(NLM_BIN="${NLM_BIN}" bash "${ADAPTER_SCRIPT}" --action smoke)"
  grep -Fqx 'notebooklm-cli adapter ready' <<<"${output}" || fail "adapter smoke output mismatch"

  echo "==> live smoke: resolve-only visual-brief"
  output="$(NLM_BIN="${NLM_BIN}" bash "${ADAPTER_SCRIPT}" \
    --action visual-brief \
    --title "NotebookLM readiness" \
    --source-manifest "${manifest}" \
    --run-dir "${run_dir}" \
    --ok-to-execute true \
    --human-approved true \
    --resolve-only)"
  grep -Fq 'nlm create' <<<"${output}" || fail "resolve-only smoke missing notebook create"
  grep -Fq 'nlm mindmap' <<<"${output}" || fail "resolve-only smoke missing mindmap create"

  if [[ "${EXECUTE_LIVE_MODE}" == "required" ]]; then
    echo "==> live smoke: execute visual-brief"
    output="$(NLM_BIN="${NLM_BIN}" bash "${ADAPTER_SCRIPT}" \
      --action visual-brief \
      --title "NotebookLM readiness" \
      --source-manifest "${manifest}" \
      --run-dir "${run_dir}" \
      --ok-to-execute true \
      --human-approved true)"
    jq -e '.artifact_id and .notebook_id and .artifact_type == "mind_map"' <<<"${output}" >/dev/null || fail "live execution did not return bounded receipt"
    [[ -f "${run_dir}/notebooklm/receipt.json" ]] || fail "live execution missing receipt.json"
  fi

  rm -rf "${smoke_tmp}"
}

main() {
  case "${LIVE_SMOKE_MODE}" in
    off|required) ;;
    *)
      fail "NOTEBOOKLM_READINESS_LIVE_SMOKE_MODE must be off or required"
      ;;
  esac
  case "${EXECUTE_LIVE_MODE}" in
    off|required) ;;
    *)
      fail "NOTEBOOKLM_READINESS_EXECUTE_LIVE_MODE must be off or required"
      ;;
  esac
  if [[ "${LIVE_SMOKE_MODE}" == "off" && "${EXECUTE_LIVE_MODE}" == "required" ]]; then
    fail "EXECUTE_LIVE_MODE=required requires LIVE_SMOKE_MODE=required"
  fi
  [[ -f "${ADAPTER_SCRIPT}" ]] || fail "adapter missing: ${ADAPTER_SCRIPT}"
  [[ -f "${SYNC_SCRIPT}" ]] || fail "sync script missing: ${SYNC_SCRIPT}"
  command -v jq >/dev/null 2>&1 || fail "missing command: jq"
  if [[ "${LIVE_SMOKE_MODE}" == "required" ]]; then
    NLM_BIN="$(notebooklm_resolve_bin "${NLM_BIN_REQUESTED}")" || exit 1
  fi

  echo "=== notebooklm runtime readiness gate ==="

  if [[ "${SKIP_REPO_TESTS}" != "true" ]]; then
    run_repo_test "tests/test-notebooklm-cli-adapter.sh"
    run_repo_test "tests/test-notebooklm-preflight-enrich.sh"
    run_repo_test "tests/test-orchestrator-nl-hints.sh"
    run_repo_test "tests/test-route-task-handoff.sh"
    run_repo_test "tests/test-fugue-bridge-handoff.sh"
    run_repo_test "tests/test-resolve-orchestration-context.sh"
  else
    echo "==> repo tests skipped (SKIP_REPO_TESTS=true)"
  fi

  check_installed_skills

  if [[ "${LIVE_SMOKE_MODE}" == "required" ]]; then
    run_live_smoke
  else
    echo "==> live smoke skipped (LIVE_SMOKE_MODE=off)"
  fi

  echo "notebooklm-runtime-readiness: PASS"
}

main "$@"
