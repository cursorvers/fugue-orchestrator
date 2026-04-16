#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

USER_HOME="${USER_HOME:-${HOME}}"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/log"
K_WRAPPER="${K_WRAPPER:-${USER_HOME}/bin/k}"

cat > "${TMP_DIR}/ssh-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${K_REMOTE_LOG}"
joined="$*"
if [[ "${joined}" == *"/remote/bin/k"* && "${joined}" == *" latest"* ]]; then
  printf 'remote-run\n'
  exit 0
fi
if [[ "${joined}" == *"/remote/bin/codex-kernel-guard"* && "${joined}" == *"doctor"* && "${joined}" == *"--all-runs"* ]]; then
  printf 'all runs:\n'
  printf '  - run_id=remote-run | project=proj | purpose=secret-plane | runtime=kernel | tmux_session=proj__secret-plane__abcd1234 | phase=implement | mode=healthy | next_action=ship | updated_at=2026-03-20T01:00:00Z | stale=false\n'
  exit 0
fi
if [[ "${joined}" == *"/remote/bin/k"* && "${joined}" == *" open"* && "${joined}" == *"remote-run"* ]]; then
  printf 'remote attach ok\n'
  exit 0
fi
if [[ "${joined}" == *"/remote/bin/k"* && "${joined}" == *" new"* && "${joined}" == *"--runtime"* && "${joined}" == *"fugue"* && "${joined}" == *"remote-review"* ]]; then
  printf 'remote fugue new ok\n'
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/ssh-stub"

export K_REMOTE_LOG="${TMP_DIR}/log/ssh.log"
export KERNEL_REMOTE_HOST="mini-host"
export KERNEL_REMOTE_USER="mini-user"
export KERNEL_REMOTE_BIN_DIR="/remote/bin"
export KERNEL_SSH_BIN="${TMP_DIR}/ssh-stub"

out="$("${K_WRAPPER}" latest)"
grep -Fq 'remote-run' <<<"${out}"
grep -Fq 'mini-user@mini-host' "${K_REMOTE_LOG}"
grep -Fq '/remote/bin/k' "${K_REMOTE_LOG}"
grep -Fq 'latest' "${K_REMOTE_LOG}"
grep -Fq 'actual_host=' "${K_REMOTE_LOG}"
grep -Fq 'mini-host' "${K_REMOTE_LOG}"

: > "${K_REMOTE_LOG}"
out="$("${K_WRAPPER}" all)"
grep -Fq 'run_id=remote-run' <<<"${out}"
grep -Fq 'runtime=kernel' <<<"${out}"
grep -Fq 'tmux_session=proj__secret-plane__abcd1234' <<<"${out}"
grep -Fq '/remote/bin/codex-kernel-guard' "${K_REMOTE_LOG}"
grep -Fq -- '--all-runs' "${K_REMOTE_LOG}"
grep -Fq 'actual_host=' "${K_REMOTE_LOG}"

: > "${K_REMOTE_LOG}"
out="$("${K_WRAPPER}" open remote-run)"
grep -Fq 'remote attach ok' <<<"${out}"
grep -Fq -- '-tt mini-user@mini-host' "${K_REMOTE_LOG}"
grep -Fq '/remote/bin/k' "${K_REMOTE_LOG}"
grep -Fq ' open' "${K_REMOTE_LOG}"
grep -Fq 'remote-run' "${K_REMOTE_LOG}"
grep -Fq 'KERNEL_PRIMARY_HOST=true' "${K_REMOTE_LOG}"
grep -Fq 'actual_host=' "${K_REMOTE_LOG}"

: > "${K_REMOTE_LOG}"
out="$("${K_WRAPPER}" new --runtime fugue remote-review)"
grep -Fq 'remote fugue new ok' <<<"${out}"
grep -Fq '/remote/bin/k' "${K_REMOTE_LOG}"
grep -Fq -- '--runtime' "${K_REMOTE_LOG}"
grep -Fq 'fugue' "${K_REMOTE_LOG}"
grep -Fq 'remote-review' "${K_REMOTE_LOG}"

export KERNEL_REMOTE_ALLOWED_HOSTS="other-host"
if "${K_WRAPPER}" latest >/dev/null 2>&1; then
  echo "k latest should fail closed when the remote host is outside the allowlist" >&2
  exit 1
fi
unset KERNEL_REMOTE_ALLOWED_HOSTS

echo "k remote check passed"
