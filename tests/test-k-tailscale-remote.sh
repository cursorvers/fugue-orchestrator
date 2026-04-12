#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/log"

cat > "${TMP_DIR}/tailscale-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${K_TS_LOG}"
joined="$*"
if [[ "${joined}" == *"ssh mini-tailnet"* && "${joined}" == *"/remote/bin/k"* && "${joined}" == *" latest"* ]]; then
  printf 'remote-tailnet-run\n'
  exit 0
fi
if [[ "${joined}" == *"ssh mini-tailnet"* && "${joined}" == *"/remote/bin/k"* && "${joined}" == *" open"* && "${joined}" == *"remote-tailnet-run"* ]]; then
  printf 'tailscale attach ok\n'
  exit 0
fi
if [[ "${joined}" == *"ssh mini-tailnet"* && "${joined}" == *"/remote/bin/k"* && "${joined}" == *" new"* && "${joined}" == *"--runtime"* && "${joined}" == *"fugue"* && "${joined}" == *"remote-fugue"* ]]; then
  printf 'tailscale fugue new ok\n'
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/tailscale-stub"

export K_TS_LOG="${TMP_DIR}/log/tailscale.log"
export KERNEL_REMOTE_TRANSPORT="tailscale-ssh"
export KERNEL_REMOTE_TARGET="mini-tailnet"
export KERNEL_REMOTE_BIN_DIR="/remote/bin"
export KERNEL_TAILSCALE_BIN="${TMP_DIR}/tailscale-stub"

out="$(/Users/masayuki_otawara/bin/k latest)"
grep -Fq 'remote-tailnet-run' <<<"${out}"
grep -Fq 'ssh mini-tailnet' "${K_TS_LOG}"
grep -Fq '/remote/bin/k' "${K_TS_LOG}"
grep -Fq 'latest' "${K_TS_LOG}"
grep -Fq 'actual_host=' "${K_TS_LOG}"
grep -Fq 'mini-tailnet' "${K_TS_LOG}"

: > "${K_TS_LOG}"
out="$(/Users/masayuki_otawara/bin/k open remote-tailnet-run)"
grep -Fq 'tailscale attach ok' <<<"${out}"
grep -Fq 'ssh mini-tailnet' "${K_TS_LOG}"
grep -Fq '/remote/bin/k' "${K_TS_LOG}"
grep -Fq ' open' "${K_TS_LOG}"
grep -Fq 'remote-tailnet-run' "${K_TS_LOG}"
grep -Fq 'actual_host=' "${K_TS_LOG}"

: > "${K_TS_LOG}"
out="$(/Users/masayuki_otawara/bin/k new --runtime fugue remote-fugue)"
grep -Fq 'tailscale fugue new ok' <<<"${out}"
grep -Fq '/remote/bin/k' "${K_TS_LOG}"
grep -Fq -- '--runtime' "${K_TS_LOG}"
grep -Fq 'fugue' "${K_TS_LOG}"
grep -Fq 'remote-fugue' "${K_TS_LOG}"

echo "k tailscale remote check passed"
