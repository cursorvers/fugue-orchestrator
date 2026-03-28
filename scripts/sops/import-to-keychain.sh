#!/usr/bin/env bash
# import-to-keychain.sh — Decrypt fugue-secrets.enc and import into macOS Keychain
# Usage: ./import-to-keychain.sh [path-to-enc-file]
# Requires: sops, age keypair at ~/.config/sops/age/keys.txt
set -euo pipefail

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

import_secret() {
  local account="$1"
  local service="$2"
  local value="$3"
  local label="$4"

  if printf '%s' "$value" | security add-generic-password -a "$account" -s "$service" -w - -U; then
    echo "  imported: $label"
  else
    echo "ERROR: failed to import $label" >&2
    exit 1
  fi
}

# Map ENV_VAR to Keychain account name
map_to_acct() {
  case "$1" in
    OPENAI_API_KEY)     echo "openai-api-key" ;;
    ANTHROPIC_API_KEY)  echo "anthropic-api-key" ;;
    GOOGLE_API_KEY)     echo "google-api-key" ;;
    MANUS_API)          echo "manus-api" ;;
    NOTION_API_KEY)     echo "notion-api-key" ;;
    N8N_API_KEY)        echo "n8n-api-key" ;;
    GEMINI_API_KEY)     echo "gemini-api-key" ;;
    TARGET_REPO_PAT)    echo "target-repo-pat" ;;
    FUGUE_OPS_PAT)      echo "fugue-ops-pat" ;;
    HOSTINGER_API)      echo "hostinger-api" ;;
    STRIPE_SECRET_KEY)  echo "stripe-secret-key" ;;
    STRIPE_API_KEY)     echo "stripe-api-key" ;;
    STRIPE_TEST_API_KEY) echo "stripe-test-api-key" ;;
    STRIPE_LIVE_API_KEY) echo "stripe-live-api-key" ;;
    ZAI_API_KEY)        echo "zai-api-key" ;;
    FREEPIK_API_KEY)    echo "freepik-api-key" ;;
    XAI_API_KEY)        echo "xai-api-key" ;;
    XAI_API)            echo "xai-api" ;;
    FREEE_CLIENT_ID)    echo "freee-client-id" ;;
    FREEE_CLIENT_SECRET) echo "freee-client-secret" ;;
    FREEE_ENCRYPTION_KEY) echo "freee-encryption-key" ;;
    FREEE_COMPANY_ID)   echo "freee-company-id" ;;
    LINE_CHANNEL_ACCESS_TOKEN) echo "line-channel-access-token" ;;
    SLACK_BOT_TOKEN)    echo "slack-bot-token" ;;
    SLACK_TEAM_ID)      echo "slack-team-id" ;;
    VERCEL_AI_GATEWAY_KEY) echo "vercel-ai-gateway-key" ;;
    SOCIALDATA_API_KEY) echo "socialdata-api-key" ;;
    NOTE_SESSION_V5)    echo "note-session-v5" ;;
    SUPABASE_SERVICE_ROLE_KEY) echo "supabase-service-role-key" ;;
    LINE_CHANNEL_SECRET) echo "line-channel-secret" ;;
    LINE_HARNESS_API_KEY) echo "line-harness-api-key" ;;
    *)                  echo "" ;;
  esac
}

echo "Decrypting: $ENC_FILE"
DECRYPTED=$(sops decrypt --input-type dotenv --output-type dotenv "$ENC_FILE")

echo "$DECRYPTED" | while IFS= read -r line; do
  # Skip comments and empty lines
  case "$line" in
    \#*|"") continue ;;
  esac

  KEY="${line%%=*}"
  VALUE="${line#*=}"

  # Special: FUGUE_QUEUE_API_KEY (different service name)
  if [ "$KEY" = "FUGUE_QUEUE_API_KEY" ]; then
    import_secret "masayuki" "FUGUE_QUEUE_API_KEY" "$VALUE" "$KEY (service: FUGUE_QUEUE_API_KEY)"
    continue
  fi

  # Special: SUPABASE_ACCESS_TOKEN (go-keyring-base64 format)
  if [ "$KEY" = "SUPABASE_ACCESS_TOKEN" ]; then
    ENCODED="go-keyring-base64:$(printf '%s' "$VALUE" | base64)"
    import_secret "supabase" "Supabase CLI" "$ENCODED" "$KEY (service: Supabase CLI)"
    continue
  fi

  # Special: x-auto service keys (account = env var name)
  case "$KEY" in
    X_API_KEY|X_API_KEY_SECRET|X_ACCESS_TOKEN|X_ACCESS_TOKEN_SECRET|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID)
      import_secret "$KEY" "x-auto" "$VALUE" "$KEY (service: x-auto)"
      continue
      ;;
  esac

  # Standard fugue-secrets entries
  ACCT=$(map_to_acct "$KEY")
  if [ -z "$ACCT" ]; then
    echo "  SKIPPED: $KEY (no mapping)"
    continue
  fi

  import_secret "$ACCT" "fugue-secrets" "$VALUE" "$KEY -> $ACCT"
done

echo "---"
echo "Done. Restart your shell to pick up new values."
