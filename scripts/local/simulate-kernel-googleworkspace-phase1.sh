#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRELIGHT_SCRIPT="${ROOT_DIR}/scripts/harness/googleworkspace-preflight-enrich.sh"

issue_number="9101"
issue_title="Kernel Google Workspace Phase 1 (simulated)"
out_dir="${ROOT_DIR}/.fugue/kernel-googleworkspace-workset/phase1-simulated"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/simulate-kernel-googleworkspace-phase1.sh [options]

Run an offline simulated Phase 1 readonly preflight for
`meeting-prep` + `standup-report` using a temporary fake adapter.

Options:
  --issue-number <n>     Issue number context (default: 9101)
  --issue-title <text>   Issue title context
  --out-dir <path>       Output directory
  -h, --help             Show help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
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
    --out-dir)
      out_dir="${2:-}"
      shift 2
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

run_dir="${out_dir%/}/run"
report_path="${out_dir%/}/phase1-simulated-report.md"
output_file="${out_dir%/}/phase1-simulated-output.txt"
mkdir -p "${out_dir}" "${run_dir}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_adapter="${tmp_dir}/googleworkspace-cli-adapter.sh"
cat > "${fake_adapter}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action=""
run_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      action="${2:-}"
      shift 2
      ;;
    --run-dir)
      run_dir="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "${run_dir}/googleworkspace"
meta_file="${run_dir}/googleworkspace/${action}-meta.json"
raw_file="${run_dir}/googleworkspace/${action}.json"

case "${action}" in
  meeting-prep)
    printf '%s' '{"summary":"next meeting at 10:00 JST with 2 linked docs","meetingCount":1}' > "${raw_file}"
    printf '%s' '{"status":"ok","message":"ok"}' > "${meta_file}"
    cat "${raw_file}"
    ;;
  standup-report)
    printf '%s' '{"summary":"meetings=3, blockers=0, followups=2","meetingCount":3}' > "${raw_file}"
    printf '%s' '{"status":"ok","message":"ok"}' > "${meta_file}"
    cat "${raw_file}"
    ;;
  *)
    printf '%s' '{"status":"error","message":"unsupported action"}' > "${meta_file}"
    echo "unsupported action" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${fake_adapter}"

env \
  ISSUE_NUMBER="${issue_number}" \
  ISSUE_TITLE="${issue_title}" \
  ISSUE_BODY="Simulated Phase 1 readonly evidence validation for meeting-prep and standup-report." \
  WORKSPACE_ACTIONS="meeting-prep,standup-report" \
  WORKSPACE_DOMAINS="calendar,drive" \
  WORKSPACE_REASON="Kernel Phase 1 offline simulation" \
  WORKSPACE_SUGGESTED_PHASES="preflight-enrich" \
  REPORT_PATH="${report_path}" \
  OUT_DIR="${out_dir}" \
  RUN_DIR="${run_dir}" \
  GITHUB_OUTPUT="${output_file}" \
  GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON='{"type":"service_account","project_id":"demo"}' \
  ADAPTER="${fake_adapter}" \
  bash "${PRELIGHT_SCRIPT}" >/dev/null

printf 'report=%s\n' "${report_path#${ROOT_DIR}/}"
printf 'run_dir=%s\n' "${run_dir#${ROOT_DIR}/}"
printf 'output=%s\n' "${output_file#${ROOT_DIR}/}"
