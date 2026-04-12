#!/usr/bin/env bash
# fugue-secret-add.sh — Add or update a secret in fugue-secrets.enc
# Usage: printf '%s' 'SECRET_VALUE' | ./fugue-secret-add.sh KEY_NAME
# SSH-safe: no interactive editor, no Keychain required
set -euo pipefail

KEY_NAME="${1:-}"

[[ $# -eq 1 && -n "$KEY_NAME" ]] || {
  echo "Usage: $0 KEY_NAME < SECRET_VALUE" >&2
  exit 1
}
[[ "$KEY_NAME" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
  echo "ERROR: KEY_NAME must match ^[A-Z][A-Z0-9_]*$" >&2
  exit 1
}

SECRET_VALUE="$(cat)"
[[ -n "$SECRET_VALUE" ]] || {
  echo "ERROR: secret value must be provided via stdin" >&2
  exit 1
}
case "$SECRET_VALUE" in
  *$'\n'*|*$'\r'*)
    echo "ERROR: secret value must be single-line" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENC_FILE="$REPO_ROOT/secrets/fugue-secrets.enc"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
ZSHENV_FILE="${ZSHENV_FILE:-$HOME/.zshenv}"
KEYMAP_FILE="${KEYMAP_FILE:-$HOME/.local/lib/fugue-sops-keymap.sh}"
export SOPS_AGE_KEY_FILE

SOPS_BIN="${SOPS_BIN:-}"
for p in /opt/homebrew/bin/sops /usr/local/bin/sops; do
  [[ -n "$SOPS_BIN" ]] && break
  [[ -x "$p" ]] && { SOPS_BIN="$p"; break; }
done
[[ -n "$SOPS_BIN" ]] || { echo "ERROR: sops not found" >&2; exit 1; }
[[ -f "$ENC_FILE" ]] || { echo "ERROR: $ENC_FILE not found" >&2; exit 1; }
[[ -f "$SOPS_AGE_KEY_FILE" ]] || { echo "ERROR: age key not found" >&2; exit 1; }
[[ -f "$ZSHENV_FILE" ]] || { echo "ERROR: $ZSHENV_FILE not found" >&2; exit 1; }

load_runtime_contract() {
  SECRET_KEYS=()
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    SECRET_KEYS+=("$key")
  done < <(
    awk '
      /^_FUGUE_SECRET_KEYS=\(/ { in_array=1; next }
      in_array && /^\)/ { in_array=0; exit }
      in_array {
        gsub(/#.*/, "", $0)
        for (i = 1; i <= NF; i++) if ($i != "") print $i
      }
    ' "$ZSHENV_FILE"
  )
}

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

runtime_sops_key_for() {
  local env_key="$1"
  local mapped
  mapped="$(
    sed -n "/^_fugue_sops_key()/,/^}/p" "$KEYMAP_FILE" \
      | grep -E "^[[:space:]]*${env_key}\)" \
      | sed -n "s/.*printf '\([^']*\)'.*/\1/p" \
      | head -n 1
  )"
  printf '%s\n' "${mapped:-$env_key}"
}

runtime_env_key_for() {
  local storage_key="$1"
  local env_key
  env_key="$(
    sed -n "/^_fugue_sops_key()/,/^}/p" "$KEYMAP_FILE" \
      | while IFS= read -r line; do
          if printf '%s\n' "$line" | grep -Fq "printf '${storage_key}'"; then
            printf '%s\n' "$line" | sed -n "s/^[[:space:]]*\([A-Z0-9_]*\)).*/\1/p"
            break
          fi
        done
  )"
  printf '%s\n' "${env_key:-$storage_key}"
}

resolve_names() {
  ENV_KEY="$KEY_NAME"
  STORAGE_KEY="$(runtime_sops_key_for "$ENV_KEY")"
  if [[ "$STORAGE_KEY" != "$KEY_NAME" ]]; then
    return 0
  fi

  ENV_KEY="$(runtime_env_key_for "$KEY_NAME")"
  if [[ "$ENV_KEY" != "$KEY_NAME" ]]; then
    STORAGE_KEY="$KEY_NAME"
  fi
}

post_write_consistency_gate() {
  local plain_file="$1"
  array_contains "$ENV_KEY" "${SECRET_KEYS[@]}" || {
    echo "ERROR: $ENV_KEY is not registered in _FUGUE_SECRET_KEYS" >&2
    exit 1
  }

  if ! awk -F= -v key="$STORAGE_KEY" '$1 == key { found = 1 } END { exit(found ? 0 : 1) }' "$plain_file"; then
    echo "ERROR: $STORAGE_KEY is missing from encrypted secret payload" >&2
    exit 1
  fi
}

TMPWORK="$(mktemp -d)"
trap 'rm -rf "$TMPWORK"' EXIT
chmod 700 "$TMPWORK"

load_runtime_contract
resolve_names

"$SOPS_BIN" decrypt --input-type dotenv --output-type dotenv "$ENC_FILE" > "$TMPWORK/plain.env" 2>/dev/null
chmod 600 "$TMPWORK/plain.env"

if awk -F= -v key="$STORAGE_KEY" '$1 == key { found = 1 } END { exit(found ? 0 : 1) }' "$TMPWORK/plain.env"; then
  awk -F= -v key="$STORAGE_KEY" '$1 != key { print }' "$TMPWORK/plain.env" > "$TMPWORK/filtered.env"
  printf '%s=%s\n' "$STORAGE_KEY" "$SECRET_VALUE" >> "$TMPWORK/filtered.env"
  mv "$TMPWORK/filtered.env" "$TMPWORK/plain.env"
  chmod 600 "$TMPWORK/plain.env"
  echo "UPDATED: $ENV_KEY"
else
  printf '%s=%s\n' "$STORAGE_KEY" "$SECRET_VALUE" >> "$TMPWORK/plain.env"
  echo "ADDED: $ENV_KEY"
fi

post_write_consistency_gate "$TMPWORK/plain.env"

cd "$REPO_ROOT"
"$SOPS_BIN" encrypt --filename-override secrets/fugue-secrets.enc \
  --input-type dotenv --output-type dotenv "$TMPWORK/plain.env" > "${ENC_FILE}.new"
mv "${ENC_FILE}.new" "$ENC_FILE"

COUNT=$("$SOPS_BIN" decrypt --input-type dotenv --output-type dotenv "$ENC_FILE" 2>/dev/null | grep -c '^[A-Z]')
echo "OK: $COUNT keys in $ENC_FILE"
