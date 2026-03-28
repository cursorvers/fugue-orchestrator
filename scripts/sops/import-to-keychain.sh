#!/usr/bin/env bash
# import-to-keychain.sh — Decrypt fugue-secrets.enc and import into macOS Keychain
# Usage: ./import-to-keychain.sh [path-to-enc-file]
# Requires: sops, age keypair at ~/.config/sops/age/keys.txt
set -eo pipefail

ENC_FILE="${1:-$(cd "$(dirname "$0")/../.." && pwd)/secrets/fugue-secrets.enc}"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
export SOPS_AGE_KEY_FILE

if [ ! -f "$ENC_FILE" ]; then
  echo "ERROR: Encrypted file not found: $ENC_FILE" >&2
  exit 1
fi

if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
  echo "ERROR: age key file not found: $SOPS_AGE_KEY_FILE" >&2
  echo "Run: age-keygen -o ~/.config/sops/age/keys.txt" >&2
  exit 1
fi

# Map ENV_VAR to Keychain account name
map_to_acct() {
  case "$1" in
    GOOGLE_API_KEY)     echo "google-api-key" ;;
    MANUS_API)          echo "manus-api" ;;
    NOTION_API_KEY)     echo "notion-api-key" ;;
    N8N_API_KEY)        echo "n8n-api-key" ;;
    GEMINI_API_KEY)     echo "gemini-api-key" ;;
    HOSTINGER_API)      echo "hostinger-api" ;;
    STRIPE_SECRET_KEY)  echo "stripe-secret-key" ;;
    STRIPE_API_KEY)     echo "stripe-api-key" ;;
    STRIPE_TEST_API_KEY) echo "stripe-test-api-key" ;;
    STRIPE_LIVE_API_KEY) echo "stripe-live-api-key" ;;
    ZAI_API_KEY)        echo "zai-api-key" ;;
    FREEPIK_API_KEY)    echo "freepik-api-key" ;;
    XAI_API)            echo "xai-api" ;;
    FREEE_CLIENT_ID)    echo "freee-client-id" ;;
    FREEE_CLIENT_SECRET) echo "freee-client-secret" ;;
    FREEE_ENCRYPTION_KEY) echo "freee-encryption-key" ;;
    FREEE_COMPANY_ID)   echo "freee-company-id" ;;
    SLACK_BOT_TOKEN)    echo "slack-bot-token" ;;
    SLACK_TEAM_ID)      echo "slack-team-id" ;;
    *)                  echo "" ;;
  esac
}

# Map x-auto keys to Keychain service "x-auto"
map_xauto_acct() {
  case "$1" in
    X_API_KEY|X_API_KEY_SECRET|X_ACCESS_TOKEN|X_ACCESS_TOKEN_SECRET)
      echo "$1" ;;  # same name as env var
    *)  echo "" ;;
  esac
}

echo "Decrypting: $ENC_FILE"
DECRYPTED=$(sops decrypt --input-type dotenv --output-type dotenv "$ENC_FILE")

IMPORTED=0
SKIPPED=0

echo "$DECRYPTED" | while IFS= read -r line; do
  # Skip comments and empty lines
  case "$line" in
    \#*|"") continue ;;
  esac

  KEY="${line%%=*}"
  VALUE="${line#*=}"

  # Special: FUGUE_QUEUE_API_KEY (different service name)
  if [ "$KEY" = "FUGUE_QUEUE_API_KEY" ]; then
    security add-generic-password -a "masayuki" -s "FUGUE_QUEUE_API_KEY" -w "$VALUE" -U 2>/dev/null || true
    echo "  imported: $KEY (service: FUGUE_QUEUE_API_KEY)"
    continue
  fi

  # Special: SUPABASE_ACCESS_TOKEN (go-keyring-base64 format)
  if [ "$KEY" = "SUPABASE_ACCESS_TOKEN" ]; then
    ENCODED="go-keyring-base64:$(printf '%s' "$VALUE" | base64)"
    security add-generic-password -a "supabase" -s "Supabase CLI" -w "$ENCODED" -U 2>/dev/null || true
    echo "  imported: $KEY (service: Supabase CLI)"
    continue
  fi

  # x-auto service keys
  XAUTO_ACCT=$(map_xauto_acct "$KEY")
  if [ -n "$XAUTO_ACCT" ]; then
    security add-generic-password -a "$XAUTO_ACCT" -s "x-auto" -w "$VALUE" -U 2>/dev/null || true
    echo "  imported: $KEY -> x-auto/$XAUTO_ACCT"
    continue
  fi

  # Standard fugue-secrets entries
  ACCT=$(map_to_acct "$KEY")
  if [ -z "$ACCT" ]; then
    echo "  SKIPPED: $KEY (no mapping)"
    continue
  fi

  security add-generic-password -a "$ACCT" -s "fugue-secrets" -w "$VALUE" -U 2>/dev/null || true
  echo "  imported: $KEY -> $ACCT"
done

echo "---"
echo "Done. Restart your shell to pick up new values."
