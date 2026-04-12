#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FETCH_SCRIPT="${SCRIPT_DIR}/scripts/harness/googleworkspace-fetch-feed-artifacts.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_bin="${tmp_dir}/bin"
mkdir -p "${fake_bin}"

cat > "${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "run" && "${2:-}" == "list" ]]; then
  workflow=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workflow)
        workflow="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  case "${workflow}" in
    googleworkspace-feed-sync.yml)
      printf '101\n'
      ;;
    googleworkspace-personal-feed-sync.yml)
      printf '202\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "run" && "${2:-}" == "download" ]]; then
  run_id="${3:-}"
  out_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        out_dir="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  mkdir -p "${out_dir}"
  case "${run_id}" in
    101)
      mkdir -p "${out_dir}/googleworkspace-feed-morning-brief-shared"
      cat > "${out_dir}/googleworkspace-feed-morning-brief-shared/latest.json" <<'JSON'
{"profile_id":"morning-brief-shared","status":"ok","summary":"standup-report: meetings=0","valid_until":"2099-01-01T00:00:00Z"}
JSON
      ;;
    202)
      mkdir -p "${out_dir}/googleworkspace-feed-morning-brief-personal"
      mkdir -p "${out_dir}/googleworkspace-feed-weekly-digest-personal"
      cat > "${out_dir}/googleworkspace-feed-morning-brief-personal/latest.json" <<'JSON'
{"profile_id":"morning-brief-personal","status":"ok","summary":"gmail-triage: resultSizeEstimate=10","valid_until":"2099-01-01T00:00:00Z"}
JSON
      cat > "${out_dir}/googleworkspace-feed-weekly-digest-personal/latest.json" <<'JSON'
{"profile_id":"weekly-digest-personal","status":"ok","summary":"weekly-digest: meetingCount=4, unreadEmails=9","valid_until":"2099-01-01T00:00:00Z"}
JSON
      ;;
    *)
      ;;
  esac
  exit 0
fi

echo "unsupported gh invocation: $*" >&2
exit 1
EOF
chmod +x "${fake_bin}/gh"

assert_ok() {
  local test_name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${test_name}]"
    failed=$((failed + 1))
  fi
}

test_downloads_and_normalizes_feed_artifacts() {
  local out_root="${tmp_dir}/out"
  env \
    PATH="${fake_bin}:${PATH}" \
    GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
    OUT_ROOT="${out_root}" \
    bash "${FETCH_SCRIPT}" >/dev/null

  [[ -f "${out_root}/morning-brief-shared/latest.json" ]] &&
    [[ -f "${out_root}/morning-brief-personal/latest.json" ]] &&
    [[ -f "${out_root}/weekly-digest-personal/latest.json" ]] &&
    jq -e '.profile_id == "morning-brief-shared"' "${out_root}/morning-brief-shared/latest.json" >/dev/null &&
    jq -e '.profile_id == "morning-brief-personal"' "${out_root}/morning-brief-personal/latest.json" >/dev/null &&
    jq -e '.profile_id == "weekly-digest-personal"' "${out_root}/weekly-digest-personal/latest.json" >/dev/null
}

echo "=== googleworkspace feed artifact fetch tests ==="
echo ""

assert_ok "downloads-and-normalizes-feed-artifacts" test_downloads_and_normalizes_feed_artifacts

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
