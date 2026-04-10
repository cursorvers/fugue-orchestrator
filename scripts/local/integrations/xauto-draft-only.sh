#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
MAX_CANDIDATES="${X_AUTO_MAX_CANDIDATES:-3}"
MIN_CHARS="${X_AUTO_MIN_CHARS:-800}"
SEED_INPUT="${X_AUTO_DRAFT_SEED_INPUT:-}"
POSTS_SEED_INPUT="${X_AUTO_DRAFT_POSTS_SEED_INPUT:-}"
REGISTRY_SEED_INPUT="${X_AUTO_DRAFT_REGISTRY_SEED_INPUT:-}"
RECENT_DRAFTS_INPUT="${X_AUTO_DRAFT_RECENT_INPUT:-}"
HANDLE="${X_AUTO_DRAFT_HANDLE:-cursorvers}"
FETCH_LIMIT="${X_AUTO_DRAFT_LOCAL_LIMIT:-20}"
FROM_DATE="${X_AUTO_DRAFT_FROM_DATE:-}"
TO_DATE="${X_AUTO_DRAFT_TO_DATE:-}"
GENERATOR_MODE="${X_AUTO_DRAFT_GENERATOR_MODE:-registry-local}" # external|registry-local
LOCAL_GENERATE_MODE="${X_AUTO_DRAFT_LOCAL_GENERATE_MODE:-auto}" # auto|xai|heuristic
LOCAL_EXTRACT_MODE="${X_AUTO_DRAFT_LOCAL_EXTRACT_MODE:-auto}" # auto|xai|heuristic
TONE_PROFILE="${X_AUTO_DRAFT_TONE_PROFILE:-middle}" # middle|polite
WRITE_NOTION_ON_EXECUTE="${X_AUTO_WRITE_NOTION_ON_EXECUTE:-true}"
ALLOW_EXTERNAL_NOTION_WRITE="${X_AUTO_ALLOW_EXTERNAL_NOTION_WRITE:-false}"
ALLOW_UNGUARDED_EXTERNAL_GENERATOR="${X_AUTO_ALLOW_UNGUARDED_EXTERNAL_GENERATOR:-false}"
REQUIRE_PROMOTABLE_ON_EXECUTE="${X_AUTO_REQUIRE_PROMOTABLE_ON_EXECUTE:-true}"
ENABLE_BLOCKED_RECOVERY="${X_AUTO_DRAFT_ENABLE_BLOCKED_RECOVERY:-false}"
BLOCKED_RECOVERY_ONLY_REASON="${X_AUTO_DRAFT_BLOCKED_RECOVERY_ONLY_REASON:-missing-non-x-primary-source}"
BLOCKED_RECOVERY_POSTS_SEED_DIR="${X_AUTO_DRAFT_BLOCKED_RECOVERY_POSTS_SEED_DIR:-}"
BLOCKED_RECOVERY_REGISTRY_INPUT="${X_AUTO_DRAFT_BLOCKED_RECOVERY_REGISTRY_INPUT:-}"
BLOCKED_RECOVERY_EXTRACT_MODE="${X_AUTO_DRAFT_BLOCKED_RECOVERY_EXTRACT_MODE:-}"
BLOCKED_RECOVERY_GENERATE_MODE="${X_AUTO_DRAFT_BLOCKED_RECOVERY_GENERATE_MODE:-}"
AUTO_SYNC_QUOTED_AUTHOR_REGISTRY="${X_AUTO_DRAFT_AUTO_SYNC_QUOTED_AUTHOR_REGISTRY:-true}"
X_AUTO_DIR="${X_AUTO_DIR:-${HOME}/Dev/x-auto}"
PYTHON_BIN="${X_AUTO_PYTHON:-${X_AUTO_DIR}/venv/bin/python}"
GENERATOR="${X_AUTO_DRAFT_GENERATOR:-${X_AUTO_DIR}/scripts/generate_draft_candidates.py}"
LOCAL_GENERATOR="${X_AUTO_DRAFT_LOCAL_GENERATOR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xauto_generate_drafts_from_registry.py}"
BLOCKED_RECOVERY_SCRIPT="${X_AUTO_DRAFT_BLOCKED_RECOVERY_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xauto-blocked-recovery.sh}"
QUOTED_AUTHOR_SYNC_SCRIPT="${X_AUTO_DRAFT_QUOTED_AUTHOR_SYNC_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xauto-quoted-author-sync.sh}"

usage() {
  cat <<'EOF'
Usage: xauto-draft-only.sh [options]

Options:
  --mode <smoke|execute>      Run mode (default: smoke)
  --run-dir <path>            FUGUE run directory (optional)
  --max-candidates <n>        Candidate limit passed to x-auto generator
  --min-chars <n>             Minimum body length passed to x-auto generator
  --seed-input <path>         Optional JSON seed array file for deterministic dry runs
  --posts-seed-input <path>   Optional raw X post JSON array for local registry generator
  --registry-seed-input <path> Optional quoted-author registry JSON for local registry generator
  --recent-drafts-input <path> Optional recent draft JSON used for similarity/diversity gating
  --generator-mode <mode>     external|registry-local (default: registry-local)
  --generate-mode <mode>      auto|xai|heuristic for registry-local mode
  --extract-mode <mode>       auto|xai|heuristic for registry-local source extraction
  --tone-profile <mode>       middle|polite for registry-local tone guard (default: middle)
  --handle <x-handle>         X handle used by registry-local mode (default: cursorvers)
  --limit <n>                 X post fetch limit for registry-local mode
  --from-date <YYYY-MM-DD>    Optional inclusive start date for registry-local mode
  --to-date <YYYY-MM-DD>      Optional inclusive end date for registry-local mode
  --auto-sync-quoted-author-registry <true|false>
                              Run advisory quoted-author registry sync after execute registry-local runs (default: true)
  -h, --help                  Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="${2:-}"
      shift 2
      ;;
    --max-candidates)
      MAX_CANDIDATES="${2:-}"
      shift 2
      ;;
    --min-chars)
      MIN_CHARS="${2:-}"
      shift 2
      ;;
    --seed-input)
      SEED_INPUT="${2:-}"
      shift 2
      ;;
    --posts-seed-input)
      POSTS_SEED_INPUT="${2:-}"
      shift 2
      ;;
    --registry-seed-input)
      REGISTRY_SEED_INPUT="${2:-}"
      shift 2
      ;;
    --recent-drafts-input)
      RECENT_DRAFTS_INPUT="${2:-}"
      shift 2
      ;;
    --generator-mode)
      GENERATOR_MODE="${2:-}"
      shift 2
      ;;
    --generate-mode)
      LOCAL_GENERATE_MODE="${2:-}"
      shift 2
      ;;
    --extract-mode)
      LOCAL_EXTRACT_MODE="${2:-}"
      shift 2
      ;;
    --tone-profile)
      TONE_PROFILE="${2:-}"
      shift 2
      ;;
    --handle)
      HANDLE="${2:-}"
      shift 2
      ;;
    --limit)
      FETCH_LIMIT="${2:-}"
      shift 2
      ;;
    --from-date)
      FROM_DATE="${2:-}"
      shift 2
      ;;
    --to-date)
      TO_DATE="${2:-}"
      shift 2
      ;;
    --auto-sync-quoted-author-registry)
      AUTO_SYNC_QUOTED_AUTHOR_REGISTRY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${MODE}" != "smoke" && "${MODE}" != "execute" ]]; then
  echo "Error: --mode must be smoke|execute" >&2
  exit 2
fi
if ! [[ "${MAX_CANDIDATES}" =~ ^[0-9]+$ ]] || (( MAX_CANDIDATES < 1 )); then
  echo "Error: --max-candidates must be an integer >= 1" >&2
  exit 2
fi
if ! [[ "${MIN_CHARS}" =~ ^[0-9]+$ ]] || (( MIN_CHARS < 1 )); then
  echo "Error: --min-chars must be an integer >= 1" >&2
  exit 2
fi
if [[ "${GENERATOR_MODE}" != "external" && "${GENERATOR_MODE}" != "registry-local" ]]; then
  echo "Error: --generator-mode must be external|registry-local" >&2
  exit 2
fi
if [[ "${LOCAL_GENERATE_MODE}" != "auto" && "${LOCAL_GENERATE_MODE}" != "xai" && "${LOCAL_GENERATE_MODE}" != "heuristic" ]]; then
  echo "Error: --generate-mode must be auto|xai|heuristic" >&2
  exit 2
fi
if [[ "${LOCAL_EXTRACT_MODE}" != "auto" && "${LOCAL_EXTRACT_MODE}" != "xai" && "${LOCAL_EXTRACT_MODE}" != "heuristic" ]]; then
  echo "Error: --extract-mode must be auto|xai|heuristic" >&2
  exit 2
fi
if [[ -z "${BLOCKED_RECOVERY_EXTRACT_MODE}" ]]; then
  BLOCKED_RECOVERY_EXTRACT_MODE="${LOCAL_EXTRACT_MODE}"
fi
if [[ -z "${BLOCKED_RECOVERY_GENERATE_MODE}" ]]; then
  BLOCKED_RECOVERY_GENERATE_MODE="${LOCAL_GENERATE_MODE}"
fi
if [[ "${BLOCKED_RECOVERY_GENERATE_MODE}" != "auto" && "${BLOCKED_RECOVERY_GENERATE_MODE}" != "xai" && "${BLOCKED_RECOVERY_GENERATE_MODE}" != "heuristic" ]]; then
  echo "Error: blocked recovery generate mode must be auto|xai|heuristic" >&2
  exit 2
fi
if [[ "${BLOCKED_RECOVERY_EXTRACT_MODE}" != "auto" && "${BLOCKED_RECOVERY_EXTRACT_MODE}" != "xai" && "${BLOCKED_RECOVERY_EXTRACT_MODE}" != "heuristic" ]]; then
  echo "Error: blocked recovery extract mode must be auto|xai|heuristic" >&2
  exit 2
fi
if [[ "${TONE_PROFILE}" != "middle" && "${TONE_PROFILE}" != "polite" ]]; then
  echo "Error: --tone-profile must be middle|polite" >&2
  exit 2
fi
if [[ "${AUTO_SYNC_QUOTED_AUTHOR_REGISTRY}" != "true" && "${AUTO_SYNC_QUOTED_AUTHOR_REGISTRY}" != "false" ]]; then
  echo "Error: --auto-sync-quoted-author-registry must be true|false" >&2
  exit 2
fi
if ! [[ "${FETCH_LIMIT}" =~ ^[0-9]+$ ]] || (( FETCH_LIMIT < 1 )); then
  echo "Error: --limit must be an integer >= 1" >&2
  exit 2
fi
if [[ -n "${SEED_INPUT}" ]]; then
  [[ -f "${SEED_INPUT}" ]] || { echo "xauto-draft-only: missing seed input: ${SEED_INPUT}" >&2; exit 1; }
fi
if [[ -n "${POSTS_SEED_INPUT}" ]]; then
  [[ -f "${POSTS_SEED_INPUT}" ]] || { echo "xauto-draft-only: missing posts seed input: ${POSTS_SEED_INPUT}" >&2; exit 1; }
fi
if [[ -n "${REGISTRY_SEED_INPUT}" ]]; then
  [[ -f "${REGISTRY_SEED_INPUT}" ]] || { echo "xauto-draft-only: missing registry seed input: ${REGISTRY_SEED_INPUT}" >&2; exit 1; }
fi
if [[ -n "${RECENT_DRAFTS_INPUT}" ]]; then
  [[ -f "${RECENT_DRAFTS_INPUT}" ]] || { echo "xauto-draft-only: missing recent drafts input: ${RECENT_DRAFTS_INPUT}" >&2; exit 1; }
fi
if [[ -n "${BLOCKED_RECOVERY_POSTS_SEED_DIR}" ]]; then
  [[ -d "${BLOCKED_RECOVERY_POSTS_SEED_DIR}" ]] || { echo "xauto-draft-only: missing blocked recovery posts seed dir: ${BLOCKED_RECOVERY_POSTS_SEED_DIR}" >&2; exit 1; }
fi

if [[ "${GENERATOR_MODE}" == "external" ]]; then
  if [[ "${ALLOW_UNGUARDED_EXTERNAL_GENERATOR}" != "true" ]]; then
    echo "xauto-draft-only: external generator mode is disabled by default because local tone and blocked guardrails are not guaranteed; use registry-local or set X_AUTO_ALLOW_UNGUARDED_EXTERNAL_GENERATOR=true for emergency smoke-only runs" >&2
    exit 2
  fi
  [[ -d "${X_AUTO_DIR}" ]] || { echo "xauto-draft-only: missing x-auto dir: ${X_AUTO_DIR}" >&2; exit 1; }
  [[ -x "${PYTHON_BIN}" ]] || { echo "xauto-draft-only: missing python runner: ${PYTHON_BIN}" >&2; exit 1; }
  [[ -f "${GENERATOR}" ]] || { echo "xauto-draft-only: missing generator: ${GENERATOR}" >&2; exit 1; }
  if [[ "${MODE}" != "smoke" ]]; then
    echo "xauto-draft-only: external generator mode is restricted to smoke runs even in break-glass mode" >&2
    exit 2
  fi
  if [[ "${MODE}" == "execute" && ( "${WRITE_NOTION_ON_EXECUTE}" == "true" || "${ALLOW_EXTERNAL_NOTION_WRITE}" == "true" ) ]]; then
    echo "xauto-draft-only: external generator mode cannot write Notion even in break-glass mode" >&2
    exit 2
  fi
else
  command -v python3 >/dev/null 2>&1 || { echo "xauto-draft-only: python3 is required for registry-local mode" >&2; exit 1; }
  [[ -f "${LOCAL_GENERATOR}" ]] || { echo "xauto-draft-only: missing local generator: ${LOCAL_GENERATOR}" >&2; exit 1; }
  if [[ "${ENABLE_BLOCKED_RECOVERY}" == "true" ]]; then
    [[ -x "${BLOCKED_RECOVERY_SCRIPT}" ]] || { echo "xauto-draft-only: missing blocked recovery script: ${BLOCKED_RECOVERY_SCRIPT}" >&2; exit 1; }
  fi
fi

cmd=()
if [[ "${GENERATOR_MODE}" == "external" ]]; then
  cmd=(
    "${PYTHON_BIN}"
    "${GENERATOR}"
    --max-candidates "${MAX_CANDIDATES}"
    --min-chars "${MIN_CHARS}"
  )
  if [[ -n "${SEED_INPUT}" ]]; then
    cmd+=(--seed-input "${SEED_INPUT}")
  fi
  if [[ "${MODE}" == "execute" && "${WRITE_NOTION_ON_EXECUTE}" == "true" ]]; then
    cmd+=(--write-notion)
  fi
else
  cmd=(
    "python3"
    "${LOCAL_GENERATOR}"
    --max-candidates "${MAX_CANDIDATES}"
    --min-chars "${MIN_CHARS}"
    --generate-mode "${LOCAL_GENERATE_MODE}"
    --tone-profile "${TONE_PROFILE}"
    --handle "${HANDLE}"
    --limit "${FETCH_LIMIT}"
    --extract-mode "${LOCAL_EXTRACT_MODE}"
  )
  if [[ -n "${REGISTRY_SEED_INPUT}" ]]; then
    cmd+=(--registry-seed-input "${REGISTRY_SEED_INPUT}")
  fi
  if [[ -n "${POSTS_SEED_INPUT}" ]]; then
    cmd+=(--posts-seed-input "${POSTS_SEED_INPUT}")
  fi
  if [[ -n "${RECENT_DRAFTS_INPUT}" ]]; then
    cmd+=(--recent-drafts-input "${RECENT_DRAFTS_INPUT}")
  fi
  if [[ -n "${FROM_DATE}" ]]; then
    cmd+=(--from-date "${FROM_DATE}")
  fi
  if [[ -n "${TO_DATE}" ]]; then
    cmd+=(--to-date "${TO_DATE}")
  fi
  if [[ -n "${RUN_DIR}" ]]; then
    cmd+=(--registry-dump-output "${RUN_DIR}/xauto-draft-only.registry.json")
  fi
fi

auto_run_dir=""
if [[ -z "${RUN_DIR}" && "${MODE}" == "execute" && "${GENERATOR_MODE}" == "registry-local" && "${ENABLE_BLOCKED_RECOVERY}" == "true" ]]; then
  auto_run_dir="$(mktemp -d)"
  RUN_DIR="${auto_run_dir}"
fi
cleanup_auto_run_dir() {
  if [[ -n "${auto_run_dir}" ]]; then
    rm -rf "${auto_run_dir}"
  fi
}
trap cleanup_auto_run_dir EXIT

echo "xauto-draft-only: mode=${MODE} generator_mode=${GENERATOR_MODE} max_candidates=${MAX_CANDIDATES} min_chars=${MIN_CHARS}"
result="$("${cmd[@]}")"

accepted_count="0"
promotable_count="0"
blocked_count="0"
rejected_count="0"
created_count="0"
recovery_summary='{}'
quoted_author_sync_status="skipped"
quoted_author_sync_bridge_status=""
quoted_author_sync_meta_path=""
if command -v jq >/dev/null 2>&1; then
  accepted_count="$(printf '%s\n' "${result}" | jq -r '.accepted | length' 2>/dev/null || printf '0')"
  promotable_count="$(printf '%s\n' "${result}" | jq -r '(.promotable // .accepted) | length' 2>/dev/null || printf '0')"
  blocked_count="$(printf '%s\n' "${result}" | jq -r '.blocked | length' 2>/dev/null || printf '0')"
  rejected_count="$(printf '%s\n' "${result}" | jq -r '.rejected | length' 2>/dev/null || printf '0')"
  created_count="$(printf '%s\n' "${result}" | jq -r '.created | length' 2>/dev/null || printf '0')"
fi

if [[ "${MODE}" == "execute" && "${GENERATOR_MODE}" == "registry-local" && "${ENABLE_BLOCKED_RECOVERY}" == "true" && "${promotable_count}" == "0" ]]; then
  mkdir -p "${RUN_DIR}"
  initial_result_path="${RUN_DIR}/xauto-draft-only.initial.result.json"
  printf '%s\n' "${result}" > "${initial_result_path}"
  registry_for_recovery="${BLOCKED_RECOVERY_REGISTRY_INPUT:-${REGISTRY_SEED_INPUT:-${RUN_DIR}/xauto-draft-only.registry.json}}"
  recovery_cmd=(
    "bash"
    "${BLOCKED_RECOVERY_SCRIPT}"
    --mode "${MODE}"
    --draft-result-input "${initial_result_path}"
    --registry-input "${registry_for_recovery}"
    --extract-mode "${BLOCKED_RECOVERY_EXTRACT_MODE}"
    --generate-mode "${BLOCKED_RECOVERY_GENERATE_MODE}"
    --only-reason "${BLOCKED_RECOVERY_ONLY_REASON}"
    --max-candidates "${MAX_CANDIDATES}"
    --min-chars "${MIN_CHARS}"
    --run-dir "${RUN_DIR}/blocked-recovery"
  )
  if [[ -n "${RECENT_DRAFTS_INPUT}" ]]; then
    recovery_cmd+=(--recent-drafts-input "${RECENT_DRAFTS_INPUT}")
  fi
  if [[ -n "${BLOCKED_RECOVERY_POSTS_SEED_DIR}" ]]; then
    recovery_cmd+=(--recovery-posts-seed-dir "${BLOCKED_RECOVERY_POSTS_SEED_DIR}")
  fi
  if [[ -n "${FROM_DATE}" ]]; then
    recovery_cmd+=(--from-date "${FROM_DATE}")
  fi
  if [[ -n "${TO_DATE}" ]]; then
    recovery_cmd+=(--to-date "${TO_DATE}")
  fi
  set +e
  recovery_result="$("${recovery_cmd[@]}")"
  recovery_rc=$?
  set -e
  recovery_summary="$(printf '%s\n' "${recovery_result}" | jq -c '.recovery // {}' 2>/dev/null || printf '{}')"
  rerun_result="$(printf '%s\n' "${recovery_result}" | jq -c '.rerun_result // {}' 2>/dev/null || printf '{}')"
  if [[ "${rerun_result}" != "{}" ]]; then
    result="$(jq -c --argjson recovery "${recovery_summary}" '. + {recovery: $recovery}' <<< "${rerun_result}")"
    accepted_count="$(printf '%s\n' "${result}" | jq -r '.accepted | length' 2>/dev/null || printf '0')"
    promotable_count="$(printf '%s\n' "${result}" | jq -r '(.promotable // .accepted) | length' 2>/dev/null || printf '0')"
    blocked_count="$(printf '%s\n' "${result}" | jq -r '.blocked | length' 2>/dev/null || printf '0')"
    rejected_count="$(printf '%s\n' "${result}" | jq -r '.rejected | length' 2>/dev/null || printf '0')"
    created_count="$(printf '%s\n' "${result}" | jq -r '.created | length' 2>/dev/null || printf '0')"
  fi
  if [[ "${recovery_rc}" != "0" && "${promotable_count}" == "0" ]]; then
    :
  fi
fi

quoted_author_sync_seed_input=""
if [[ -n "${REGISTRY_SEED_INPUT}" ]]; then
  quoted_author_sync_seed_input="${REGISTRY_SEED_INPUT}"
elif [[ -n "${RUN_DIR}" && -f "${RUN_DIR}/xauto-draft-only.registry.json" ]]; then
  quoted_author_sync_seed_input="${RUN_DIR}/xauto-draft-only.registry.json"
fi

if [[ "${MODE}" == "execute" && "${GENERATOR_MODE}" == "registry-local" && "${AUTO_SYNC_QUOTED_AUTHOR_REGISTRY}" == "true" && -n "${quoted_author_sync_seed_input}" ]]; then
  if [[ -f "${QUOTED_AUTHOR_SYNC_SCRIPT}" ]]; then
    sync_run_dir=""
    if [[ -n "${RUN_DIR}" ]]; then
      sync_run_dir="${RUN_DIR}/quoted-author-sync"
    elif [[ -n "${auto_run_dir:-}" ]]; then
      sync_run_dir="${auto_run_dir}/quoted-author-sync"
    fi
    sync_cmd=(
      "bash"
      "${QUOTED_AUTHOR_SYNC_SCRIPT}"
      --mode "${MODE}"
      --seed-input "${quoted_author_sync_seed_input}"
      --handle "${HANDLE}"
      --limit "${FETCH_LIMIT}"
      --extract-mode "${LOCAL_EXTRACT_MODE}"
    )
    if [[ -n "${sync_run_dir}" ]]; then
      sync_cmd+=(--run-dir "${sync_run_dir}")
    fi
    if [[ -n "${POSTS_SEED_INPUT}" ]]; then
      sync_cmd+=(--posts-seed-input "${POSTS_SEED_INPUT}")
    fi
    if [[ -n "${FROM_DATE}" ]]; then
      sync_cmd+=(--from-date "${FROM_DATE}")
    fi
    if [[ -n "${TO_DATE}" ]]; then
      sync_cmd+=(--to-date "${TO_DATE}")
    fi
    set +e
    sync_output="$("${sync_cmd[@]}" 2>&1)"
    sync_rc=$?
    set -e
    if (( sync_rc != 0 )); then
      quoted_author_sync_status="failed"
    fi
    if [[ -n "${sync_run_dir}" ]]; then
      quoted_author_sync_meta_path="${sync_run_dir}/xauto-quoted-author-sync.meta"
      if [[ -f "${quoted_author_sync_meta_path}" ]]; then
        quoted_author_sync_bridge_status="$(awk -F= '/^bridge_status=/{print $2}' "${quoted_author_sync_meta_path}" | tail -n1)"
      fi
    fi
    if (( sync_rc == 0 )); then
      if [[ -n "${quoted_author_sync_bridge_status}" ]]; then
        quoted_author_sync_status="${quoted_author_sync_bridge_status}"
      else
        quoted_author_sync_status="completed-no-bridge-status"
      fi
    fi
    if [[ "${quoted_author_sync_status}" == "failed" ]]; then
      echo "xauto-draft-only: advisory quoted-author sync failed" >&2
      echo "${sync_output}" >&2
    fi
  else
    quoted_author_sync_status="missing-script"
  fi
fi

printf '%s\n' "${result}"

if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
  printf '%s\n' "${result}" > "${RUN_DIR}/xauto-draft-only.result.json"
  if [[ "${GENERATOR_MODE}" == "registry-local" ]] && command -v jq >/dev/null 2>&1; then
    printf '%s\n' "${result}" | jq '{
      generator: .generator,
      mode: "execute",
      dispatchable: (.promotable // .accepted // []),
      blocked: (.blocked // []),
      recovery: (.recovery // {}),
      closeout: (.closeout // {}),
      summary: (.summary // {})
    }' > "${RUN_DIR}/xauto-draft-only.dispatch.json"
  fi
  {
    echo "system=x-auto-draft-only"
    echo "mode=${MODE}"
    echo "generator_mode=${GENERATOR_MODE}"
    echo "x_auto_dir=${X_AUTO_DIR}"
    echo "python_bin=${PYTHON_BIN}"
    echo "generator=${GENERATOR}"
    echo "local_generator=${LOCAL_GENERATOR}"
    echo "max_candidates=${MAX_CANDIDATES}"
    echo "min_chars=${MIN_CHARS}"
    echo "handle=${HANDLE}"
    echo "limit=${FETCH_LIMIT}"
    echo "from_date=${FROM_DATE}"
    echo "to_date=${TO_DATE}"
    echo "generate_mode=${LOCAL_GENERATE_MODE}"
    echo "extract_mode=${LOCAL_EXTRACT_MODE}"
    echo "tone_profile=${TONE_PROFILE}"
    echo "write_notion_on_execute=${WRITE_NOTION_ON_EXECUTE}"
    echo "allow_external_notion_write=${ALLOW_EXTERNAL_NOTION_WRITE}"
    echo "allow_unguarded_external_generator=${ALLOW_UNGUARDED_EXTERNAL_GENERATOR}"
    echo "require_promotable_on_execute=${REQUIRE_PROMOTABLE_ON_EXECUTE}"
    echo "enable_blocked_recovery=${ENABLE_BLOCKED_RECOVERY}"
    echo "blocked_recovery_only_reason=${BLOCKED_RECOVERY_ONLY_REASON}"
    echo "blocked_recovery_extract_mode=${BLOCKED_RECOVERY_EXTRACT_MODE}"
    echo "blocked_recovery_generate_mode=${BLOCKED_RECOVERY_GENERATE_MODE}"
    echo "auto_sync_quoted_author_registry=${AUTO_SYNC_QUOTED_AUTHOR_REGISTRY}"
    echo "quoted_author_sync_status=${quoted_author_sync_status}"
    if [[ -n "${quoted_author_sync_bridge_status}" ]]; then
      echo "quoted_author_sync_bridge_status=${quoted_author_sync_bridge_status}"
    fi
    if [[ -n "${quoted_author_sync_meta_path}" ]]; then
      echo "quoted_author_sync_meta_path=${quoted_author_sync_meta_path}"
    fi
    echo "issue_title=${FUGUE_ISSUE_TITLE:-}"
    echo "issue_url=${FUGUE_ISSUE_URL:-}"
    if [[ -n "${SEED_INPUT}" ]]; then
      echo "seed_input=${SEED_INPUT}"
    fi
    if [[ -n "${REGISTRY_SEED_INPUT}" ]]; then
      echo "registry_seed_input=${REGISTRY_SEED_INPUT}"
    fi
    if [[ -n "${POSTS_SEED_INPUT}" ]]; then
      echo "posts_seed_input=${POSTS_SEED_INPUT}"
    fi
    if [[ -n "${RECENT_DRAFTS_INPUT}" ]]; then
      echo "recent_drafts_input=${RECENT_DRAFTS_INPUT}"
    fi
    echo "accepted_count=${accepted_count}"
    echo "promotable_count=${promotable_count}"
    echo "blocked_count=${blocked_count}"
    echo "rejected_count=${rejected_count}"
    echo "created_count=${created_count}"
    if command -v jq >/dev/null 2>&1; then
      blocked_summary="$(printf '%s\n' "${result}" | jq -c '.closeout // {}' 2>/dev/null || printf '{}')"
      echo "blocked_summary=${blocked_summary}"
      echo "recovery_summary=${recovery_summary}"
    fi
  } > "${RUN_DIR}/xauto-draft-only.meta"
fi

if [[ "${MODE}" == "execute" && "${GENERATOR_MODE}" == "registry-local" && "${REQUIRE_PROMOTABLE_ON_EXECUTE}" == "true" ]]; then
  if [[ "${promotable_count}" == "0" ]]; then
    echo "xauto-draft-only: execute completed but no promotable candidates were produced" >&2
    exit 4
  fi
fi
