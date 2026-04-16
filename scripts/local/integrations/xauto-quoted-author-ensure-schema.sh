#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
MIGRATION_FILE=""

usage() {
  cat <<'EOF'
Usage: xauto-quoted-author-ensure-schema.sh [options]

Options:
  --mode <smoke|execute>      Verify only or apply migration (default: smoke)
  --run-dir <path>            Output directory (optional)
  --project-ref <ref>         Supabase project ref (optional if derivable)
  --migration-file <path>     SQL file to apply in execute mode
  -h, --help                  Show help

Environment:
  SUPABASE_ACCESS_TOKEN       Required for execute mode
  SUPABASE_SERVICE_ROLE_KEY   Required for verification
  SUPABASE_URL                Optional; used for verification and ref derivation
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
    --project-ref)
      PROJECT_REF="${2:-}"
      shift 2
      ;;
    --migration-file)
      MIGRATION_FILE="${2:-}"
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
  echo "xauto-quoted-author-ensure-schema: --mode must be smoke|execute" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEFAULT_MIGRATION="${ROOT_DIR}/supabase/migrations/20260406193000_x_auto_quoted_author_registry_v1.sql"
if [[ -z "${MIGRATION_FILE}" ]]; then
  MIGRATION_FILE="${DEFAULT_MIGRATION}"
fi

command -v curl >/dev/null 2>&1 || { echo "xauto-quoted-author-ensure-schema: curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "xauto-quoted-author-ensure-schema: jq is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "xauto-quoted-author-ensure-schema: python3 is required" >&2; exit 1; }
[[ -f "${MIGRATION_FILE}" ]] || { echo "xauto-quoted-author-ensure-schema: missing migration file: ${MIGRATION_FILE}" >&2; exit 1; }

derive_project_ref() {
  if [[ -n "${PROJECT_REF}" ]]; then
    printf '%s' "${PROJECT_REF}"
    return 0
  fi
  if [[ -n "${SUPABASE_URL:-}" ]]; then
    python3 - "${SUPABASE_URL}" <<'PY'
import re
import sys
url = sys.argv[1].strip()
m = re.match(r"https://([a-z0-9]+)\.supabase\.co/?", url)
print(m.group(1) if m else "")
PY
    return 0
  fi
  if [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    python3 - "${SUPABASE_SERVICE_ROLE_KEY}" <<'PY'
import base64
import json
import sys
token = sys.argv[1]
parts = token.split(".")
if len(parts) < 2:
    print("")
    raise SystemExit(0)
payload = parts[1]
payload += "=" * (-len(payload) % 4)
try:
    data = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
except Exception:
    print("")
    raise SystemExit(0)
print(data.get("ref", ""))
PY
    return 0
  fi
  printf '%s' ""
}

derive_supabase_url() {
  if [[ -n "${SUPABASE_URL:-}" ]]; then
    printf '%s' "${SUPABASE_URL}"
    return 0
  fi
  local ref="$1"
  if [[ -n "${ref}" ]]; then
    printf 'https://%s.supabase.co' "${ref}"
    return 0
  fi
  printf '%s' ""
}

run_dir=""
if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
  run_dir="${RUN_DIR}"
else
  run_dir="$(mktemp -d)"
fi

result_path="${run_dir}/xauto-quoted-author-ensure-schema.result.json"
meta_path="${run_dir}/xauto-quoted-author-ensure-schema.meta"
verify_path="${run_dir}/xauto-quoted-author-ensure-schema.verify.json"
apply_path="${run_dir}/xauto-quoted-author-ensure-schema.apply.json"

project_ref="$(derive_project_ref)"
supabase_url="$(derive_supabase_url "${project_ref}")"
verify_http="n/a"
apply_http="n/a"
status="not-run"

if [[ -n "${supabase_url}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  verify_http="$(curl -sS -o "${verify_path}" -w '%{http_code}' "${supabase_url}/rest/v1/quoted_authors?select=author_id&limit=1" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")"
  if [[ "${verify_http}" == "200" || "${verify_http}" == "206" ]]; then
    status="schema-present"
  elif [[ "${verify_http}" == "404" ]]; then
    status="schema-missing"
  else
    status="verify-error"
  fi
else
  status="verify-skipped-missing-creds"
fi

if [[ "${MODE}" == "execute" && "${status}" == "schema-missing" ]]; then
  [[ -n "${project_ref}" ]] || { echo "xauto-quoted-author-ensure-schema: project ref unavailable" >&2; exit 1; }
  [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]] || { echo "xauto-quoted-author-ensure-schema: SUPABASE_ACCESS_TOKEN is required for execute mode" >&2; exit 1; }
  sql_body="$(jq -Rs '{query: .}' < "${MIGRATION_FILE}")"
  apply_http="$(curl -sS -o "${apply_path}" -w '%{http_code}' "https://api.supabase.com/v1/projects/${project_ref}/database/query" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${sql_body}")"
  verify_http="$(curl -sS -o "${verify_path}" -w '%{http_code}' "${supabase_url}/rest/v1/quoted_authors?select=author_id&limit=1" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")"
  if [[ "${apply_http}" =~ ^20[01]$|^204$ ]] && [[ "${verify_http}" == "200" || "${verify_http}" == "206" ]]; then
    status="schema-applied"
  else
    status="apply-error"
  fi
fi

jq -n \
  --arg mode "${MODE}" \
  --arg project_ref "${project_ref}" \
  --arg supabase_url "${supabase_url}" \
  --arg status "${status}" \
  --arg verify_http "${verify_http}" \
  --arg apply_http "${apply_http}" \
  --arg migration_file "${MIGRATION_FILE}" \
  '{
    system: "xauto-quoted-author-ensure-schema",
    mode: $mode,
    project_ref: $project_ref,
    supabase_url: $supabase_url,
    status: $status,
    verify_http: $verify_http,
    apply_http: $apply_http,
    migration_file: $migration_file
  }' > "${result_path}"

{
  echo "system=xauto-quoted-author-ensure-schema"
  echo "mode=${MODE}"
  echo "project_ref=${project_ref}"
  echo "supabase_url=${supabase_url}"
  echo "status=${status}"
  echo "verify_http=${verify_http}"
  echo "apply_http=${apply_http}"
  echo "migration_file=${MIGRATION_FILE}"
  echo "result_path=${result_path}"
} > "${meta_path}"

cat "${result_path}"
