#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/compact" "${TMP_DIR}/state" "${TMP_DIR}/log"

cat > "${HOME}/bin/k" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KN_TEST_LOG}"
EOF
chmod +x "${HOME}/bin/k"

cat > "${TMP_DIR}/tmux-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
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
export KN_SELECT=1

TS_A="$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
TS_B="$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"

cat > "${TMP_DIR}/compact/run-a.json" <<EOF
{"run_id":"run-a","project":"fugue-orchestrator","purpose":"secret-plane","runtime":"kernel","tmux_session":"fugue-orchestrator__secret-plane","current_phase":"implement","mode":"healthy","next_action":["wire secret loader"],"updated_at":"${TS_A}"}
EOF

cat > "${TMP_DIR}/compact/run-b.json" <<EOF
{"run_id":"run-b","project":"fugue-orchestrator","purpose":"tmux-handoff","runtime":"fugue","tmux_session":"fugue-orchestrator__tmux-handoff","current_phase":"critique","mode":"degraded","next_action":["tighten doctor output"],"updated_at":"${TS_B}"}
EOF

out="$(/Users/masayuki_otawara/bin/kn)"
grep -Fq '進行中の開発一覧:' <<<"${out}"
grep -Fq "1) fugue-orchestrator:secret-plane / runtime=kernel / tmux=fugue-orchestrator__secret-plane / フェーズ=implement / 状態=healthy / 次=wire secret loader / 更新=${TS_A}" <<<"${out}"
grep -Fq "2) fugue-orchestrator:tmux-handoff / runtime=fugue / tmux=fugue-orchestrator__tmux-handoff / フェーズ=critique / 状態=degraded / 次=tighten doctor output / 更新=${TS_B}" <<<"${out}"
if grep -Fq 'run-a' <<<"${out}" || grep -Fq 'run-b' <<<"${out}"; then
  echo "kn should not expose raw run ids in interactive list" >&2
  exit 1
fi
grep -Fq 'run-a' "${KN_TEST_LOG}"

echo "kn selector check passed"
