#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

USER_HOME="${USER_HOME:-${HOME}}"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/compact" "${TMP_DIR}/log"
KN_WRAPPER="${KN_WRAPPER:-${USER_HOME}/bin/kn}"

cat > "${HOME}/bin/k" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'k %s\n' "$*" >> "${KN_TEST_LOG}"
EOF
chmod +x "${HOME}/bin/k"

cat > "${TMP_DIR}/tmux-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KN_TMUX_LOG}"
case "${1:-}" in
  list-sessions)
    printf 'cmux\n'
    printf 'stale-managed\n'
    ;;
  list-windows)
    if [[ "${3:-}" == "=stale-managed" ]]; then
      printf 'main\n'
    else
      printf 'proj-a\n'
      printf 'proj-b\n'
    fi
    ;;
  has-session)
    exit 1
    ;;
  select-window|attach)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "${TMP_DIR}/tmux-stub"

export K_BIN="${HOME}/bin/k"
export TMUX_BIN="${TMP_DIR}/tmux-stub"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KN_TEST_LOG="${TMP_DIR}/log/kn.log"
export KN_TMUX_LOG="${TMP_DIR}/log/tmux.log"
export KN_SELECT=2
export KERNEL_STALE_HOURS=24

cat > "${TMP_DIR}/compact/run-stale.json" <<'EOF'
{"run_id":"run-stale","project":"cmux","purpose":"stale-managed","tmux_session":"stale-managed","current_phase":"critique","mode":"degraded","next_action":["resume"],"updated_at":"2026-03-18T00:00:00Z"}
EOF

out="$("${KN_WRAPPER}")"
grep -Fq '進行中の開発一覧:' <<<"${out}"
grep -Fq '1) cmux:proj-a / 状態=unmanaged / 次=Kernel run に昇格' <<<"${out}"
grep -Fq '2) cmux:proj-b / 状態=unmanaged / 次=Kernel run に昇格' <<<"${out}"
if grep -Fq 'stale-managed:main' <<<"${out}"; then
  echo "stale managed sessions must not be reclassified as unmanaged units" >&2
  exit 1
fi
grep -Fq 'k adopt cmux:proj-b' "${KN_TEST_LOG}"

echo "kn unmanaged selector check passed"
