#!/usr/bin/env bash
# secrets-verify.sh — Verify sops SSoT matches Keychain. Auto-repair if --fix.
# Usage: ./secrets-verify.sh [--fix] [--quiet]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENC_FILE="${SCRIPT_DIR}/../../secrets/fugue-secrets.enc"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
export SOPS_AGE_KEY_FILE

FIX_MODE=false; QUIET=false
for arg in "$@"; do
  case "$arg" in
    --fix) FIX_MODE=true ;;
    --quiet) QUIET=true ;;
  esac
done

PASS=0; FAIL=0; FIXED=0; TOTAL=0
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

log() { $QUIET || echo "$@"; }

# Map key to its service+account in Keychain
resolve_keychain_location() {
  local key="$1"
  case "$key" in
    FUGUE_QUEUE_API_KEY)
      echo "FUGUE_QUEUE_API_KEY|$(whoami)" ;;
    SUPABASE_ACCESS_TOKEN)
      echo "Supabase CLI|supabase" ;;
    X_API_KEY|X_API_KEY_SECRET|X_ACCESS_TOKEN|X_ACCESS_TOKEN_SECRET|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|SLACK_WEBHOOK_URL)
      echo "x-auto|$key" ;;
    NOTION_API_KEY)
      echo "x-auto|$key" ;;
    *)
      echo "fugue-secrets|$key" ;;
  esac
}

check_key() {
  local key="$1" expected="$2"
  local location
  location=$(resolve_keychain_location "$key")
  local service="${location%%|*}"
  local account="${location#*|}"
  TOTAL=$((TOTAL + 1))

  local actual
  actual=$(security find-generic-password -s "$service" -a "$account" -w 2>/dev/null) || actual=""

  # Special handling for Supabase (base64 encoded)
  if [ "$key" = "SUPABASE_ACCESS_TOKEN" ]; then
    expected="go-keyring-base64:$(printf '%s' "$expected" | base64)"
  fi

  if [ -z "$actual" ]; then
    FAIL=$((FAIL + 1))
    log "  MISSING: $key (service=$service, account=$account)"
    if $FIX_MODE; then
      if security add-generic-password -a "$account" -s "$service" -w "$expected" -U 2>/dev/null; then
        FIXED=$((FIXED + 1)); log "    FIXED: $key"
      else
        log "    FIX FAILED: $key"
      fi
    fi
  elif [ "$actual" = "-" ]; then
    FAIL=$((FAIL + 1))
    log "  CORRUPTED: $key = '-' (known import bug)"
    if $FIX_MODE; then
      security delete-generic-password -s "$service" -a "$account" 2>/dev/null
      if security add-generic-password -a "$account" -s "$service" -w "$expected" -U 2>/dev/null; then
        FIXED=$((FIXED + 1)); log "    FIXED: $key"
      fi
    fi
  elif [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    log "  MISMATCH: $key (keychain != sops)"
    if $FIX_MODE; then
      security delete-generic-password -s "$service" -a "$account" 2>/dev/null
      if security add-generic-password -a "$account" -s "$service" -w "$expected" -U 2>/dev/null; then
        FIXED=$((FIXED + 1)); log "    FIXED: $key"
      fi
    fi
  fi
}

log "Secrets verification: sops SSoT vs Keychain"
log "============================================"

if [ ! -f "$ENC_FILE" ]; then
  echo "ERROR: $ENC_FILE not found" >&2; exit 1
fi

sops decrypt --input-type dotenv --output-type dotenv "$ENC_FILE" > "$TMPFILE" 2>/dev/null
if [ ! -s "$TMPFILE" ]; then
  echo "ERROR: sops decrypt failed" >&2; exit 1
fi

while IFS= read -r line; do
  case "$line" in \#*|"") continue ;; esac
  KEY="${line%%=*}"
  VALUE="${line#*=}"
  check_key "$KEY" "$VALUE"
done < "$TMPFILE"

log ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL PASS: $PASS/$TOTAL keys verified"
  exit 0
else
  log "RESULT: $PASS passed, $FAIL failed ($FIXED fixed) out of $TOTAL"
  $FIX_MODE || log "Run with --fix to auto-repair"
  exit 1
fi
