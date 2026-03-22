#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/compact" "${TMP_DIR}/log"

cat > "${HOME}/bin/codex-kernel-guard" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${K_TEST_LOG}"
if [[ "${1:-}" == "recover-run" ]]; then
  session="$(jq -r '.tmux_session // ""' "${KERNEL_COMPACT_DIR}/$(printf '%s' "${2:-}" | tr '/:' '__').json")"
  printf '%s\n' "${session}" >> "${TMUX_RECOVERED_FILE}"
  exit 0
fi
EOF
chmod +x "${HOME}/bin/codex-kernel-guard"

cat > "${HOME}/bin/kernel" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'kernel purpose=%s auto=%s args=%s\n' "${KERNEL_PURPOSE:-}" "${KERNEL_AUTO_OPEN_LATEST:-}" "$*" >> "${K_TEST_LOG}"
EOF
chmod +x "${HOME}/bin/kernel"

cat > "${HOME}/bin/fugue" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'fugue purpose=%s runtime=%s focus=%s\n' "${KERNEL_PURPOSE:-}" "${KERNEL_RUNTIME:-}" "$*" >> "${K_TEST_LOG}"
EOF
chmod +x "${HOME}/bin/fugue"

cat > "${TMP_DIR}/tmux-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    target="${3:-}"
    target="${target#=}"
    if [[ -f "${TMUX_RECOVERED_FILE:-}" ]] && grep -Fxq "${target}" "${TMUX_RECOVERED_FILE}"; then
      exit 0
    fi
    case ",${TMUX_LIVE_SESSIONS:-}," in
      *,"${target}",*)
        exit 0
        ;;
    esac
    if [[ "${TMUX_HAS_SESSION:-false}" == "true" ]]; then
      exit 0
    fi
    exit 1
    ;;
  show-options)
    target="${3:-}"
    option_name="${5:-}"
    if [[ "${target}" == "${TMUX_SHOW_OPTION_SESSION:-}" && "${option_name}" == "${TMUX_SHOW_OPTION_NAME:-}" ]]; then
      printf '%s\n' "${TMUX_SHOW_OPTION_VALUE:-}"
      exit 0
    fi
    exit 1
    ;;
  new-session)
    printf 'new-session %s\n' "$*" >> "${TMUX_ACTION_LOG}"
    ;;
  new-window)
    printf 'new-window %s\n' "$*" >> "${TMUX_ACTION_LOG}"
    ;;
  send-keys)
    printf 'send-keys %s\n' "$*" >> "${TMUX_ACTION_LOG}"
    ;;
  attach)
    printf 'attach %s\n' "${3:-}"
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "${TMP_DIR}/tmux-stub"

export K_TEST_LOG="${TMP_DIR}/log/guard.log"
export KERNEL_GUARD_BIN="${HOME}/bin/codex-kernel-guard"
export KERNEL_BIN="${HOME}/bin/kernel"
export FUGUE_BIN="${HOME}/bin/fugue"
export TMUX_BIN="${TMP_DIR}/tmux-stub"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_K_NO_ATTACH=true
export TMUX_RECOVERED_FILE="${TMP_DIR}/log/recovered-sessions.log"
export TMUX_ACTION_LOG="${TMP_DIR}/log/tmux-actions.log"

iso_hours_ago() {
  python3 - "$1" <<'PY'
import datetime
import sys

hours = int(sys.argv[1])
ts = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
print(ts.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

FRESH_TS="$(iso_hours_ago 1)"
OLDER_TS="$(iso_hours_ago 2)"
STALE_TS="$(iso_hours_ago 30)"

cat > "${TMP_DIR}/compact/run-1.json" <<'EOF'
{"run_id":"run-1","tmux_session":"proj__purpose","project":"proj","purpose":"purpose","session_fingerprint":"fingerprint-run-1"}
EOF
cat > "${TMP_DIR}/compact/run-2.json" <<'EOF'
{"run_id":"run-2","tmux_session":"proj__second","project":"proj","purpose":"second","updated_at":"OLDER_TS_PLACEHOLDER"}
EOF
cat > "${TMP_DIR}/compact/run-3.json" <<'EOF'
{"run_id":"run-3","tmux_session":"proj__latest","project":"proj","purpose":"latest","updated_at":"FRESH_TS_PLACEHOLDER"}
EOF
cat > "${TMP_DIR}/compact/run-old.json" <<'EOF'
{"run_id":"run-old","tmux_session":"proj__old","project":"proj","purpose":"old","updated_at":"STALE_TS_PLACEHOLDER"}
EOF

python3 - "${TMP_DIR}" "${OLDER_TS}" "${FRESH_TS}" "${STALE_TS}" <<'PY'
import pathlib
import sys

tmp_dir = pathlib.Path(sys.argv[1])
replacements = {
    "OLDER_TS_PLACEHOLDER": sys.argv[2],
    "FRESH_TS_PLACEHOLDER": sys.argv[3],
    "STALE_TS_PLACEHOLDER": sys.argv[4],
}
for path in tmp_dir.joinpath("compact").glob("*.json"):
    text = path.read_text(encoding="utf-8")
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
PY

/Users/masayuki_otawara/bin/k >/dev/null
grep -Fq 'doctor' "${K_TEST_LOG}"

/Users/masayuki_otawara/bin/k all >/dev/null
grep -Fq 'doctor --all-runs' "${K_TEST_LOG}"

/Users/masayuki_otawara/bin/k show run-1 >/dev/null
grep -Fq 'doctor --run run-1' "${K_TEST_LOG}"

export TMUX_HAS_SESSION=true
export TMUX_LIVE_SESSIONS='proj__latest,proj__purpose'
out="$(/Users/masayuki_otawara/bin/k latest)"
grep -Fq 'run-3' <<<"${out}"

out="$(/Users/masayuki_otawara/bin/k run-id)"
grep -Fq 'run-3' <<<"${out}"

export TMUX_LIVE_SESSIONS='proj__old'
export TMUX_HAS_SESSION=false
if /Users/masayuki_otawara/bin/k latest >/dev/null 2>&1; then
  echo "k latest should ignore stale runs even if the tmux session still exists" >&2
  exit 1
fi

/Users/masayuki_otawara/bin/k phase implement >/dev/null
grep -Fq 'phase-complete implement' "${K_TEST_LOG}"

/Users/masayuki_otawara/bin/k new secret-plane >/dev/null
grep -Fq 'new-session -d -s fugue-orchestrator__secret-plane -n main' "${TMUX_ACTION_LOG}"
grep -Fq 'new-window -t =fugue-orchestrator__secret-plane -n logs' "${TMUX_ACTION_LOG}"
grep -Fq 'send-keys -t =fugue-orchestrator__secret-plane:main' "${TMUX_ACTION_LOG}"
grep -Fq 'KERNEL_TMUX_SESSION=fugue-orchestrator__secret-plane' "${TMUX_ACTION_LOG}"
grep -Fq 'KERNEL_PURPOSE=secret-plane' "${TMUX_ACTION_LOG}"
grep -Fq 'kernel' "${TMUX_ACTION_LOG}"

/Users/masayuki_otawara/bin/k new runtime-enforcement focus-text >/dev/null
grep -Fq 'new-session -d -s fugue-orchestrator__runtime-enforcement -n main' "${TMUX_ACTION_LOG}"
grep -Fq 'focus-text' "${TMUX_ACTION_LOG}"

/Users/masayuki_otawara/bin/k new --runtime fugue fugue-handoff review-claude >/dev/null
grep -Fq 'new-session -d -s fugue-orchestrator__fugue-handoff -n main' "${TMUX_ACTION_LOG}"
grep -Fq "${HOME}/bin/fugue" "${TMUX_ACTION_LOG}"
grep -Fq 'KERNEL_RUNTIME=fugue' "${TMUX_ACTION_LOG}"
grep -Fq 'review-claude' "${TMUX_ACTION_LOG}"

/Users/masayuki_otawara/bin/k adopt cmux:proj-a gws >/dev/null
grep -Fq 'adopt-run cmux:proj-a gws' "${K_TEST_LOG}"

/Users/masayuki_otawara/bin/k done ship it >/dev/null
grep -Fq 'run-complete --summary ship it' "${K_TEST_LOG}"

export TMUX_HAS_SESSION=true
export TMUX_LIVE_SESSIONS='proj__purpose'
out="$(/Users/masayuki_otawara/bin/k open run-1)"
grep -Fq 'attach proj__purpose' <<<"${out}"

out="$(/Users/masayuki_otawara/bin/k run-1)"
grep -Fq 'attach proj__purpose' <<<"${out}"

export TMUX_LIVE_SESSIONS='proj__latest'
export TMUX_HAS_SESSION=true
out="$(/Users/masayuki_otawara/bin/k open)"
grep -Fq 'attach proj__latest' <<<"${out}"

export TMUX_LIVE_SESSIONS='proj__purpose'
export TMUX_HAS_SESSION=true
export TMUX_SHOW_OPTION_SESSION='proj__purpose'
export TMUX_SHOW_OPTION_NAME='@kernel_run_id'
export TMUX_SHOW_OPTION_VALUE='run-other'
if /Users/masayuki_otawara/bin/k open run-1 >/dev/null 2>&1; then
  echo "k open should reject a tmux session owned by a different run" >&2
  exit 1
fi
unset TMUX_SHOW_OPTION_SESSION TMUX_SHOW_OPTION_NAME TMUX_SHOW_OPTION_VALUE

export TMUX_HAS_SESSION=false
export TMUX_LIVE_SESSIONS=''
: > "${K_TEST_LOG}"
if out="$(/Users/masayuki_otawara/bin/k open run-1 2>&1)"; then
  echo "operator host should not auto-recover a missing session" >&2
  exit 1
fi
grep -Fq 'session missing locally for run run-1' <<<"${out}"
if grep -Fq 'recover-run run-1' "${K_TEST_LOG}"; then
  echo "operator host should require explicit recover-run" >&2
  exit 1
fi

export KERNEL_NODE_ROLE=primary
: > "${K_TEST_LOG}"
out="$(/Users/masayuki_otawara/bin/k open run-1)"
grep -Fq 'attach proj__purpose' <<<"${out}"
grep -Fq 'recover-run run-1' "${K_TEST_LOG}"

echo "k shortcuts check passed"
