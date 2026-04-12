#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/log"

cat > "${TMP_DIR}/ssh-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KN_REMOTE_LOG}"
printf '進行中の開発一覧:\n'
printf '1) proj:secret-plane / runtime=kernel / tmux=proj__secret-plane__abcd1234 / フェーズ=implement / 状態=healthy / 次=ship / 更新=2026-03-20T01:00:00Z\n'
printf '2) proj:secret-plane / runtime=fugue / tmux=proj__secret-plane__beef5678 / フェーズ=implement / 状態=healthy / 次=review / 更新=2026-03-20T00:59:00Z\n'
EOF
chmod +x "${TMP_DIR}/ssh-stub"

export KN_REMOTE_LOG="${TMP_DIR}/log/ssh.log"
export KERNEL_REMOTE_TARGET="mini-host"
export KERNEL_REMOTE_BIN_DIR="/remote/bin"
export KERNEL_SSH_BIN="${TMP_DIR}/ssh-stub"

out="$(/Users/masayuki_otawara/bin/kn)"
grep -Fq '1) proj:secret-plane / runtime=kernel / tmux=proj__secret-plane__abcd1234' <<<"${out}"
grep -Fq '2) proj:secret-plane / runtime=fugue / tmux=proj__secret-plane__beef5678' <<<"${out}"
grep -Fq -- '-tt mini-host' "${KN_REMOTE_LOG}"
grep -Fq '/remote/bin/kn' "${KN_REMOTE_LOG}"
grep -Fq 'KN_AUTO_OPEN_SINGLE=false' "${KN_REMOTE_LOG}"
grep -Fq 'actual_host=' "${KN_REMOTE_LOG}"
grep -Fq 'mini-host' "${KN_REMOTE_LOG}"

export KERNEL_REMOTE_ALLOWED_HOSTS="other-host"
if /Users/masayuki_otawara/bin/kn >/dev/null 2>&1; then
  echo "kn should fail closed when the remote host is outside the allowlist" >&2
  exit 1
fi

echo "kn remote check passed"
