#!/usr/bin/env bash
set -euo pipefail

ISSUE_NUMBER="${ISSUE_NUMBER:-}"
ISSUE_TITLE="${ISSUE_TITLE:-}"
ISSUE_BODY="${ISSUE_BODY:-}"
CONTENT_HINT_APPLIED="${CONTENT_HINT_APPLIED:-false}"
CONTENT_ACTION_HINT="${CONTENT_ACTION_HINT:-}"
CONTENT_SKILL_HINT="${CONTENT_SKILL_HINT:-}"
CONTENT_REASON="${CONTENT_REASON:-}"
OUT_DIR="${OUT_DIR:-.fugue/pre-implement}"
RUN_DIR="${RUN_DIR:-${OUT_DIR}/notebooklm-run}"
REPORT_PATH="${REPORT_PATH:-${OUT_DIR}/issue-${ISSUE_NUMBER}-notebooklm.md}"
ADAPTER="${ADAPTER:-scripts/lib/notebooklm-cli-adapter.sh}"
RESEARCH_REPORT_PATH="${RESEARCH_REPORT_PATH:-}"
PLAN_REPORT_PATH="${PLAN_REPORT_PATH:-}"
CRITIC_REPORT_PATH="${CRITIC_REPORT_PATH:-}"
NOTEBOOKLM_RUNTIME_ENABLED="${NOTEBOOKLM_RUNTIME_ENABLED:-false}"
NOTEBOOKLM_REQUIRE_RUNTIME_AUTH="${NOTEBOOKLM_REQUIRE_RUNTIME_AUTH:-false}"
NOTEBOOKLM_HUMAN_APPROVED="${NOTEBOOKLM_HUMAN_APPROVED:-false}"
NOTEBOOKLM_SENSITIVITY="${NOTEBOOKLM_SENSITIVITY:-internal}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/notebooklm-bin.sh
source "${SCRIPT_DIR}/../lib/notebooklm-bin.sh"
NLM_BIN_REQUESTED="${NLM_BIN:-${FUGUE_NOTEBOOKLM_BIN:-nlm}}"
NLM_BIN="${NLM_BIN_REQUESTED}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

sanitize_summary() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g'
}

append_csv_unique() {
  local current="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    printf '%s' "${current}"
    return 0
  fi
  case ",${current}," in
    *,"${value}",*)
      printf '%s' "${current}"
      ;;
    *)
      if [[ -z "${current}" ]]; then
        printf '%s' "${value}"
      else
        printf '%s,%s' "${current}" "${value}"
      fi
      ;;
  esac
}

contains_notebooklm_action() {
  local csv="$1"
  local item
  while IFS= read -r item; do
    item="$(printf '%s' "${item}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    case "${item}" in
      notebooklm-visual-brief|notebooklm-slide-prep)
        return 0
        ;;
    esac
  done < <(printf '%s\n' "${csv}" | tr ',' '\n')
  return 1
}

resolve_action() {
  local csv="$1"
  local item
  while IFS= read -r item; do
    item="$(printf '%s' "${item}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    case "${item}" in
      notebooklm-slide-prep)
        printf '%s' "slide-prep"
        return 0
        ;;
      notebooklm-visual-brief)
        printf '%s' "visual-brief"
        return 0
        ;;
    esac
  done < <(printf '%s\n' "${csv}" | tr ',' '\n')
  return 1
}

adapter_action=""
source_manifest_path=""
issue_source_path=""
summary_csv=""
report_status="skipped"
runtime_mode="contract-only"
receipt_path=""
commands_path=""
meta_path=""

write_report() {
  local notes_message="$1"
  {
    echo "# Issue #${ISSUE_NUMBER} NotebookLM Artifact"
    echo
    echo "- status: ${report_status}"
    echo "- issue: ${ISSUE_TITLE}"
    echo "- action: ${adapter_action:-none}"
    echo "- reason: ${CONTENT_REASON:-none}"
    echo "- runtime mode: ${runtime_mode}"
    echo "- run dir: ${RUN_DIR}"
    echo "- source manifest: ${source_manifest_path:-none}"
    echo "- receipt path: ${receipt_path:-none}"
    echo
    echo "## Summary"
    echo
    echo "${summary_csv}"
    echo
    echo "## Notes"
    echo
    echo "- NotebookLM remains artifact-only peripheral evidence."
    echo "- Use bounded receipts and stable references only."
    echo "- ${notes_message}"
    if [[ -n "${commands_path}" && -f "${commands_path}" ]]; then
      echo
      echo "## Resolved Commands"
      echo
      sed -n '1,12p' "${commands_path}"
    fi
  } > "${REPORT_PATH}"
}

emit_outputs() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "notebooklm_preflight_status=${report_status}"
      echo "notebooklm_report_path=${REPORT_PATH}"
      echo "notebooklm_receipt_path=${receipt_path}"
      echo "notebooklm_summary<<EOF"
      echo "${summary_csv}"
      echo "EOF"
    } >> "${GITHUB_OUTPUT}"
  fi
}

build_source_manifest() {
  local source_dir="${RUN_DIR%/}/sources"
  local ndjson_path="${RUN_DIR%/}/source-manifest.ndjson"
  source_manifest_path="${RUN_DIR%/}/source-manifest.json"

  mkdir -p "${OUT_DIR}" "${RUN_DIR}" "${source_dir}"
  : > "${ndjson_path}"

  issue_source_path="${source_dir}/issue-${ISSUE_NUMBER}.md"
  {
    echo "# Issue #${ISSUE_NUMBER}"
    echo
    echo "## Title"
    echo "${ISSUE_TITLE}"
    echo
    echo "## Body"
    echo "${ISSUE_BODY}"
    echo
    echo "## Content Reason"
    echo "${CONTENT_REASON:-none}"
  } > "${issue_source_path}"

  jq -cn --arg value "${issue_source_path}" '{type:"file", value:$value, wait:true}' >> "${ndjson_path}"

  local candidate
  for candidate in "${RESEARCH_REPORT_PATH}" "${PLAN_REPORT_PATH}" "${CRITIC_REPORT_PATH}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      jq -cn --arg value "${candidate}" '{type:"file", value:$value, wait:true}' >> "${ndjson_path}"
    fi
  done

  jq -s '{sources:.}' "${ndjson_path}" > "${source_manifest_path}"
}

run_preflight() {
  local action_flag=""
  local output_file="${RUN_DIR%/}/notebooklm-preflight.stdout"
  local stderr_file="${RUN_DIR%/}/notebooklm-preflight.stderr"
  local smoke_output="${RUN_DIR%/}/notebooklm-smoke.stdout"

  case "${adapter_action}" in
    visual-brief)
      action_flag="visual-brief"
      ;;
    slide-prep)
      action_flag="slide-prep"
      ;;
    *)
      fail "unsupported adapter action: ${adapter_action}"
      ;;
  esac

  meta_path="${RUN_DIR%/}/notebooklm/${action_flag}-meta.json"
  commands_path="${RUN_DIR%/}/notebooklm/${action_flag}.commands.txt"
  receipt_path="${RUN_DIR%/}/notebooklm/receipt.json"

  local runtime_enabled
  runtime_enabled="$(normalize_bool "${NOTEBOOKLM_RUNTIME_ENABLED}")"
  local require_runtime_auth
  require_runtime_auth="$(normalize_bool "${NOTEBOOKLM_REQUIRE_RUNTIME_AUTH}")"
  local human_approved
  human_approved="$(normalize_bool "${NOTEBOOKLM_HUMAN_APPROVED}")"
  local runtime_available="false"

  if [[ "${runtime_enabled}" == "true" ]]; then
    if NLM_BIN="$(notebooklm_resolve_bin "${NLM_BIN_REQUESTED}" 2>/dev/null)" && \
      NLM_BIN="${NLM_BIN}" bash "${ADAPTER}" --action smoke > "${smoke_output}" 2>/dev/null; then
      runtime_available="true"
    fi
  fi

  if [[ "${runtime_available}" == "true" && "${human_approved}" == "true" ]]; then
    runtime_mode="execute"
    if [[ "${action_flag}" == "visual-brief" ]]; then
      bash "${ADAPTER}" \
        --action "${action_flag}" \
        --title "Issue ${ISSUE_NUMBER} NotebookLM Preflight" \
        --source-manifest "${source_manifest_path}" \
        --run-dir "${RUN_DIR}" \
        --sensitivity "${NOTEBOOKLM_SENSITIVITY}" \
        --ok-to-execute true \
        --human-approved true \
        --artifact-type mind_map > "${output_file}" 2> "${stderr_file}" || {
          report_status="partial"
          summary_csv="NotebookLM adapter execution failed."
          write_report "Runtime adapter execution failed."
          emit_outputs
          if [[ "${require_runtime_auth}" == "true" ]]; then
            exit 1
          fi
          return 0
        }
    else
      bash "${ADAPTER}" \
        --action "${action_flag}" \
        --title "Issue ${ISSUE_NUMBER} NotebookLM Preflight" \
        --source-manifest "${source_manifest_path}" \
        --run-dir "${RUN_DIR}" \
        --sensitivity "${NOTEBOOKLM_SENSITIVITY}" \
        --ok-to-execute true \
        --human-approved true > "${output_file}" 2> "${stderr_file}" || {
          report_status="partial"
          summary_csv="NotebookLM adapter execution failed."
          write_report "Runtime adapter execution failed."
          emit_outputs
          if [[ "${require_runtime_auth}" == "true" ]]; then
            exit 1
          fi
          return 0
        }
    fi
    report_status="verified"
    if [[ -f "${receipt_path}" ]]; then
      summary_csv="$(jq -r '"artifact_type=\(.artifact_type), artifact_id=\(.artifact_id), notebook_id=\(.notebook_id)"' "${receipt_path}" 2>/dev/null || true)"
    fi
    if [[ -z "${summary_csv}" ]]; then
      summary_csv="NotebookLM artifact generated."
    fi
    write_report "Runtime NotebookLM execution completed on the runner."
    emit_outputs
    return 0
  fi

  runtime_mode="contract-only"
  if [[ "${require_runtime_auth}" == "true" ]]; then
    report_status="blocked"
    summary_csv="NotebookLM runtime execution is required but unavailable."
    write_report "NotebookLM runtime/auth was unavailable, so execution was blocked."
    emit_outputs
    exit 1
  fi

  if [[ "${action_flag}" == "visual-brief" ]]; then
    bash "${ADAPTER}" \
      --action "${action_flag}" \
      --title "Issue ${ISSUE_NUMBER} NotebookLM Preflight" \
      --source-manifest "${source_manifest_path}" \
      --run-dir "${RUN_DIR}" \
      --sensitivity "${NOTEBOOKLM_SENSITIVITY}" \
      --ok-to-execute true \
      --human-approved true \
      --resolve-only \
      --artifact-type mind_map > "${output_file}" 2> "${stderr_file}"
  else
    bash "${ADAPTER}" \
      --action "${action_flag}" \
      --title "Issue ${ISSUE_NUMBER} NotebookLM Preflight" \
      --source-manifest "${source_manifest_path}" \
      --run-dir "${RUN_DIR}" \
      --sensitivity "${NOTEBOOKLM_SENSITIVITY}" \
      --ok-to-execute true \
      --human-approved true \
      --resolve-only > "${output_file}" 2> "${stderr_file}"
  fi

  report_status="planned"
  summary_csv="NotebookLM commands resolved without live execution."
  write_report "Runtime execution was skipped; resolved commands are staged for later operator-approved use."
  emit_outputs
}

main() {
  require_cmd jq
  [[ -n "${ISSUE_NUMBER}" ]] || fail "ISSUE_NUMBER is required"
  [[ -x "${ADAPTER}" ]] || fail "adapter missing or not executable: ${ADAPTER}"

  if [[ "$(normalize_bool "${CONTENT_HINT_APPLIED}")" != "true" ]]; then
    summary_csv="No content hint was applied."
    mkdir -p "${OUT_DIR}" "${RUN_DIR}"
    write_report "NotebookLM preflight did not run because content hints were inactive."
    emit_outputs
    exit 0
  fi

  if contains_notebooklm_action "${CONTENT_ACTION_HINT}"; then
    adapter_action="$(resolve_action "${CONTENT_ACTION_HINT}")"
  elif contains_notebooklm_action "${CONTENT_SKILL_HINT}"; then
    adapter_action="$(resolve_action "${CONTENT_SKILL_HINT}")"
  else
    summary_csv="No NotebookLM content action was suggested."
    mkdir -p "${OUT_DIR}" "${RUN_DIR}"
    write_report "NotebookLM preflight did not run because no NotebookLM action hint was present."
    emit_outputs
    exit 0
  fi

  build_source_manifest
  run_preflight
}

main "$@"
