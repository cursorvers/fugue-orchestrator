#!/usr/bin/env bash
set -euo pipefail

MODE="execute"
DRAFT_RESULT_INPUT=""
REGISTRY_INPUT=""
EXTRACT_MODE="${X_AUTO_DRAFT_BLOCKED_RECOVERY_EXTRACT_MODE:-heuristic}"
GENERATE_MODE="${X_AUTO_DRAFT_BLOCKED_RECOVERY_GENERATE_MODE:-heuristic}"
ONLY_REASON="${X_AUTO_DRAFT_BLOCKED_RECOVERY_ONLY_REASON:-missing-non-x-primary-source}"
MAX_CANDIDATES="${X_AUTO_MAX_CANDIDATES:-3}"
MIN_CHARS="${X_AUTO_MIN_CHARS:-800}"
RUN_DIR=""
RECENT_DRAFTS_INPUT="${X_AUTO_DRAFT_RECENT_INPUT:-}"
RECOVERY_POSTS_SEED_DIR="${X_AUTO_DRAFT_BLOCKED_RECOVERY_POSTS_SEED_DIR:-}"
FROM_DATE="${X_AUTO_DRAFT_FROM_DATE:-}"
TO_DATE="${X_AUTO_DRAFT_TO_DATE:-}"
HANDLE="${X_AUTO_DRAFT_HANDLE:-cursorvers}"
PYTHON_BIN="${X_AUTO_PYTHON:-python3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_GENERATOR="${X_AUTO_DRAFT_LOCAL_GENERATOR:-${SCRIPT_DIR}/xauto_generate_drafts_from_registry.py}"
SYNC_HELPER="${SCRIPT_DIR}/xauto_quoted_author_sync.py"

usage() {
  cat <<'EOF'
Usage: xauto-blocked-recovery.sh [options]

Options:
  --mode <smoke|execute>            Mode passed through to recovery metadata
  --draft-result-input <path>       Initial xauto_generate_drafts_from_registry result JSON
  --registry-input <path>           Original registry seed input JSON
  --extract-mode <mode>             auto|xai|heuristic for recovery extraction
  --generate-mode <mode>            auto|xai|heuristic for rerun generation
  --only-reason <reason>            Block reason to target (default: missing-non-x-primary-source)
  --max-candidates <n>              Candidate limit for rerun
  --min-chars <n>                   Minimum chars for rerun
  --run-dir <path>                  Optional run directory for artifacts
  --recent-drafts-input <path>      Optional recent draft JSON for similarity guard
  --recovery-posts-seed-dir <path>  Directory of post JSON seeds used to recover primary sources
  --from-date <YYYY-MM-DD>          Optional date range passthrough
  --to-date <YYYY-MM-DD>            Optional date range passthrough
  -h, --help                        Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --draft-result-input) DRAFT_RESULT_INPUT="${2:-}"; shift 2 ;;
    --registry-input) REGISTRY_INPUT="${2:-}"; shift 2 ;;
    --extract-mode) EXTRACT_MODE="${2:-}"; shift 2 ;;
    --generate-mode) GENERATE_MODE="${2:-}"; shift 2 ;;
    --only-reason) ONLY_REASON="${2:-}"; shift 2 ;;
    --max-candidates) MAX_CANDIDATES="${2:-}"; shift 2 ;;
    --min-chars) MIN_CHARS="${2:-}"; shift 2 ;;
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --recent-drafts-input) RECENT_DRAFTS_INPUT="${2:-}"; shift 2 ;;
    --recovery-posts-seed-dir) RECOVERY_POSTS_SEED_DIR="${2:-}"; shift 2 ;;
    --from-date) FROM_DATE="${2:-}"; shift 2 ;;
    --to-date) TO_DATE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ "${MODE}" == "smoke" || "${MODE}" == "execute" ]] || { echo "mode must be smoke|execute" >&2; exit 2; }
[[ -f "${DRAFT_RESULT_INPUT}" ]] || { echo "missing draft result input: ${DRAFT_RESULT_INPUT}" >&2; exit 1; }
[[ -f "${REGISTRY_INPUT}" ]] || { echo "missing registry input: ${REGISTRY_INPUT}" >&2; exit 1; }
[[ -f "${LOCAL_GENERATOR}" ]] || { echo "missing local generator: ${LOCAL_GENERATOR}" >&2; exit 1; }
[[ -f "${SYNC_HELPER}" ]] || { echo "missing sync helper: ${SYNC_HELPER}" >&2; exit 1; }
command -v "${PYTHON_BIN}" >/dev/null 2>&1 || { echo "missing python: ${PYTHON_BIN}" >&2; exit 1; }
if [[ -n "${RECOVERY_POSTS_SEED_DIR}" ]]; then
  [[ -d "${RECOVERY_POSTS_SEED_DIR}" ]] || { echo "missing recovery posts seed dir: ${RECOVERY_POSTS_SEED_DIR}" >&2; exit 1; }
fi
if [[ -n "${RECENT_DRAFTS_INPUT}" ]]; then
  [[ -f "${RECENT_DRAFTS_INPUT}" ]] || { echo "missing recent drafts input: ${RECENT_DRAFTS_INPUT}" >&2; exit 1; }
fi

if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
else
  RUN_DIR="$(mktemp -d)"
fi

MERGED_REGISTRY_PATH="${RUN_DIR}/xauto-blocked-recovery.registry.json"
RECOVERY_META_PATH="${RUN_DIR}/xauto-blocked-recovery.recovery.json"
RERUN_RESULT_PATH="${RUN_DIR}/xauto-blocked-recovery.result.json"

RECOVERY_JSON="$("${PYTHON_BIN}" - "${DRAFT_RESULT_INPUT}" "${REGISTRY_INPUT}" "${ONLY_REASON}" "${RECOVERY_POSTS_SEED_DIR}" "${MERGED_REGISTRY_PATH}" "${HANDLE}" "${SCRIPT_DIR}" <<'PY'
import json
import sys
from pathlib import Path

draft_result_path = Path(sys.argv[1])
registry_input_path = Path(sys.argv[2])
only_reason = sys.argv[3]
recovery_seed_dir = Path(sys.argv[4]) if sys.argv[4] else None
merged_registry_path = Path(sys.argv[5])
self_handle = sys.argv[6]
script_dir = Path(sys.argv[7])

sys.path.insert(0, str(script_dir))
import xauto_quoted_author_sync as sync_helper  # noqa: E402


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)


def normalize_registry(payload):
    if isinstance(payload, list):
        return payload, "list"
    if isinstance(payload, dict) and isinstance(payload.get("records"), list):
        return payload["records"], "records-object"
    raise RuntimeError("registry input must be a list or {records:[...]}")


def restore_registry(records, shape):
    if shape == "list":
        return records
    return {"records": records}


def collect_targets(result_payload):
    targets = []
    for item in result_payload.get("blocked", []) or []:
        if str(item.get("blocked_reason_canonical", "")).strip() != only_reason:
            continue
        targets.append(
            {
                "draft_id": str(item.get("draft_id", "")).strip(),
                "source_url": str(item.get("source_url", "")).strip(),
                "author_handle": str(item.get("quoted_author_handle", "")).strip().lower(),
            }
        )
    if not targets:
        for item in ((result_payload.get("closeout") or {}).get("backfill_targets", []) or []):
            source_url = str(item.get("source_url", "")).strip()
            author_handle = str(item.get("quoted_author_handle", "")).strip().lower()
            if source_url or author_handle:
                targets.append(
                    {
                        "draft_id": str(item.get("draft_id", "")).strip(),
                        "source_url": source_url,
                        "author_handle": author_handle,
                    }
                )
    deduped = []
    seen = set()
    for target in targets:
        key = (target["source_url"], target["author_handle"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(target)
    return deduped


def build_recovered_records(seed_dir: Path | None):
    by_source = {}
    by_author = {}
    used_files = []
    if not seed_dir or not seed_dir.exists():
        return by_source, by_author, used_files
    for seed_file in sorted(seed_dir.glob("*.json")):
        posts = sync_helper.load_posts_from_seed(str(seed_file))
        records = sync_helper.postprocess_records(sync_helper.heuristic_extract(posts, self_handle), posts)
        if not records:
            continue
        used_files.append(seed_file.name)
        for record in records:
            source_url = str(record.get("source_url", "")).strip()
            author_handle = str(record.get("author_handle", "")).strip().lower()
            primary_url = str((record.get("metadata") or {}).get("primary_source_url", "")).strip()
            if source_url and primary_url and source_url not in by_source:
                by_source[source_url] = record
            if author_handle and primary_url and author_handle not in by_author:
                by_author[author_handle] = record
    return by_source, by_author, used_files


result_payload = load_json(draft_result_path)
registry_payload = load_json(registry_input_path)
registry_records, registry_shape = normalize_registry(registry_payload)
targets = collect_targets(result_payload)
recovered_by_source, recovered_by_author, used_files = build_recovered_records(recovery_seed_dir)

patched_count = 0
recovered_count = 0
recovery_notes = []
records = [dict(item) for item in registry_records]

for target in targets:
    recovered = None
    if target["source_url"]:
      recovered = recovered_by_source.get(target["source_url"])
    if recovered is None and target["author_handle"]:
      recovered = recovered_by_author.get(target["author_handle"])
    if recovered is None:
      recovery_notes.append({"target": target, "status": "unresolved"})
      continue

    recovered_meta = dict(recovered.get("metadata") or {})
    primary_url = str(recovered_meta.get("primary_source_url", "")).strip()
    if not primary_url:
      recovery_notes.append({"target": target, "status": "missing-primary-source"})
      continue

    match_index = None
    for idx, record in enumerate(records):
      source_url = str(record.get("source_url", "")).strip()
      author_handle = str(record.get("author_handle", "")).strip().lower()
      if target["source_url"] and source_url == target["source_url"]:
        match_index = idx
        break
      if target["author_handle"] and author_handle == target["author_handle"]:
        match_index = idx
        break

    if match_index is None:
      records.append(recovered)
      patched_count += 1
      recovered_count += 1
      recovery_notes.append({"target": target, "status": "appended", "primary_source_url": primary_url})
      continue

    record = dict(records[match_index])
    metadata = dict(record.get("metadata") or {})
    metadata["primary_source_url"] = primary_url
    metadata["primary_source_confidence"] = recovered_meta.get("primary_source_confidence", 0.8)
    metadata["primary_source_strategy"] = recovered_meta.get("primary_source_strategy", "author-conversation")
    if recovered_meta.get("source_hash"):
      metadata["source_hash"] = recovered_meta["source_hash"]
    if recovered_meta.get("event_hash"):
      metadata["event_hash"] = recovered_meta["event_hash"]
    if recovered_meta.get("confidence") is not None:
      metadata["confidence"] = recovered_meta.get("confidence")
    record["metadata"] = metadata
    records[match_index] = record
    patched_count += 1
    recovered_count += 1
    recovery_notes.append({"target": target, "status": "patched", "primary_source_url": primary_url})

merged_registry = restore_registry(records, registry_shape)
dump_json(merged_registry_path, merged_registry)

summary = {
    "mode": "blocked-recovery",
    "attempted_count": len(targets),
    "recovered_count": recovered_count,
    "patched_count": patched_count,
    "seed_files_used": used_files,
    "notes": recovery_notes,
    "registry_path": str(merged_registry_path),
}
print(json.dumps(summary, ensure_ascii=False))
PY
)"

printf '%s\n' "${RECOVERY_JSON}" > "${RECOVERY_META_PATH}"

RERUN_ARGS=(
  "${PYTHON_BIN}"
  "${LOCAL_GENERATOR}"
  --handle "${HANDLE}"
  --registry-seed-input "${MERGED_REGISTRY_PATH}"
  --extract-mode "${EXTRACT_MODE}"
  --generate-mode "${GENERATE_MODE}"
  --max-candidates "${MAX_CANDIDATES}"
  --min-chars "${MIN_CHARS}"
  --registry-dump-output "${RUN_DIR}/xauto-blocked-recovery.registry-dump.json"
)
if [[ -n "${RECENT_DRAFTS_INPUT}" ]]; then
  RERUN_ARGS+=(--recent-drafts-input "${RECENT_DRAFTS_INPUT}")
fi
if [[ -n "${FROM_DATE}" ]]; then
  RERUN_ARGS+=(--from-date "${FROM_DATE}")
fi
if [[ -n "${TO_DATE}" ]]; then
  RERUN_ARGS+=(--to-date "${TO_DATE}")
fi

RERUN_RESULT="$("${RERUN_ARGS[@]}")"
printf '%s\n' "${RERUN_RESULT}" > "${RERUN_RESULT_PATH}"

"${PYTHON_BIN}" - "${RECOVERY_META_PATH}" "${RERUN_RESULT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

recovery = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
rerun_result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
json.dump({"recovery": recovery, "rerun_result": rerun_result}, sys.stdout, ensure_ascii=False)
PY
