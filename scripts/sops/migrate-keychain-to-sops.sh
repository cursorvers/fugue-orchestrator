#!/usr/bin/env bash
# migrate-keychain-to-sops.sh — Add Keychain-only keys to fugue-secrets.enc
# Run from GUI terminal where Keychain is unlocked.
# One-time migration: 9 keys missing from sops (2026-03-22)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENC_FILE="$REPO_ROOT/secrets/fugue-secrets.enc"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
export SOPS_AGE_KEY_FILE
SOPS_BIN="${SOPS_BIN:-/opt/homebrew/bin/sops}"

# Preflight
for f in "$ENC_FILE" "$SOPS_AGE_KEY_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: not found: $f" >&2; exit 1; }
done
[[ -x "$SOPS_BIN" ]] || { echo "ERROR: sops not found at $SOPS_BIN" >&2; exit 1; }

# Check Keychain accessibility (try multiple probe keys)
KC_OK=0
for probe in google-api-key stripe-api-key anthropic-api-key gemini-api-key; do
  if security find-generic-password -s fugue-secrets -a "$probe" -w >/dev/null 2>&1; then
    KC_OK=1; break
  fi
done
if (( ! KC_OK )); then
  # Also check x-auto service
  security find-generic-password -s x-auto -a X_API_KEY -w >/dev/null 2>&1 && KC_OK=1
fi
if (( ! KC_OK )); then
  echo "ERROR: Keychain inaccessible (all probe keys failed)." >&2
  echo "Try: security unlock-keychain ~/Library/Keychains/login.keychain-db" >&2
  exit 1
fi

echo "Keychain accessible. Reading missing keys..."

# Keys to migrate: (sops_key, keychain_service, keychain_account)
declare -a MIGRATIONS=(
  "OPENAI_API_KEY|fugue-secrets|openai-api-key"
  "ANTHROPIC_API_KEY|fugue-secrets|anthropic-api-key"
  "TARGET_REPO_PAT|fugue-secrets|target-repo-pat"
  "FUGUE_OPS_PAT|fugue-secrets|fugue-ops-pat"
  "VERCEL_AI_GATEWAY_KEY|fugue-secrets|vercel-ai-gateway-key"
  "X_API_KEY|x-auto|X_API_KEY"
  "X_API_KEY_SECRET|x-auto|X_API_KEY_SECRET"
  "X_ACCESS_TOKEN|x-auto|X_ACCESS_TOKEN"
  "X_ACCESS_TOKEN_SECRET|x-auto|X_ACCESS_TOKEN_SECRET"
)

# Decrypt current sops to temp (auto-cleanup)
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT
PLAIN="$TMPDIR_WORK/secrets.env"
chmod 700 "$TMPDIR_WORK"

"$SOPS_BIN" decrypt --input-type dotenv --output-type dotenv "$ENC_FILE" > "$PLAIN" 2>/dev/null
chmod 600 "$PLAIN"

EXISTING_KEYS="$(awk -F= '/^[A-Z]/{print $1}' "$PLAIN")"
ADDED=0

for entry in "${MIGRATIONS[@]}"; do
  IFS='|' read -r sops_key kc_service kc_account <<< "$entry"

  # Skip if already in sops
  if echo "$EXISTING_KEYS" | grep -qx "$sops_key"; then
    echo "  SKIP: $sops_key (already in sops)"
    continue
  fi

  # Read from Keychain
  val="$(security find-generic-password -s "$kc_service" -a "$kc_account" -w 2>/dev/null)" || {
    echo "  WARN: $sops_key not in Keychain ($kc_service/$kc_account)"
    continue
  }
  if [[ -z "$val" ]]; then
    echo "  WARN: $sops_key empty in Keychain"
    continue
  fi

  echo "${sops_key}=${val}" >> "$PLAIN"
  echo "  ADD:  $sops_key (${#val} chars from $kc_service)"
  (( ADDED++ ))
done

if (( ADDED == 0 )); then
  echo "No keys to add. Done."
  exit 0
fi

# Re-encrypt (cd to repo root so sops finds .sops.yaml)
echo "Re-encrypting with $ADDED new keys..."
cd "$REPO_ROOT"
"$SOPS_BIN" encrypt --filename-override secrets/fugue-secrets.enc --input-type dotenv --output-type dotenv "$PLAIN" > "${ENC_FILE}.new"
mv "${ENC_FILE}.new" "$ENC_FILE"
echo "Updated: $ENC_FILE ($ADDED keys added)"

# Verify round-trip
VERIFY_COUNT="$("$SOPS_BIN" decrypt --input-type dotenv --output-type dotenv "$ENC_FILE" 2>/dev/null | grep -c '^[A-Z]')"
echo "Verification: $VERIFY_COUNT keys in encrypted file"

echo "---"
echo "Next steps:"
echo "  1. git diff secrets/fugue-secrets.enc  (verify changes)"
echo "  2. git add secrets/fugue-secrets.enc && git commit"
echo "  3. import-to-keychain.sh on other machines"
