#!/bin/bash
# x-auto shared environment bootstrap
# Source this from all x-auto launcher scripts
# Usage: source "$(dirname "$0")/x-auto-env.sh" [KEY1 KEY2 ...]

export HOME="/Users/masayuki_otawara"
export PYTHONPATH="$HOME/.local/share/x-auto/venv/lib/python3.13/site-packages"

_X_AUTO_ENC="$HOME/fugue-orchestrator/secrets/fugue-secrets.enc"
_X_AUTO_AGE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# Find sops binary
_X_AUTO_SOPS=""
for _p in /opt/homebrew/bin/sops /usr/local/bin/sops; do
  [[ -x "$_p" ]] && { _X_AUTO_SOPS="$_p"; break; }
done

# Export requested secrets from sops
# If no args given, export nothing (caller handles its own key list)
x_auto_load_secrets() {
  local keys="${*:-}"
  [[ -z "$keys" ]] && return 0
  [[ -z "$_X_AUTO_SOPS" || ! -f "$_X_AUTO_ENC" || ! -f "$_X_AUTO_AGE" ]] && return 1

  local plain
  plain="$(SOPS_AGE_KEY_FILE="$_X_AUTO_AGE" "$_X_AUTO_SOPS" decrypt \
    --input-type dotenv --output-type dotenv "$_X_AUTO_ENC" 2>/dev/null)" || return 1

  local rkey val
  for rkey in $keys; do
    val="$(echo "$plain" | grep "^${rkey}=" | head -1 | cut -d= -f2-)"
    [[ -n "$val" ]] && export "$rkey=$val"
  done
  unset plain val
}
