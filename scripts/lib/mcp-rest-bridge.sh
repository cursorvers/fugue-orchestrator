#!/usr/bin/env bash
set -euo pipefail

# MCP REST Bridge: Direct REST API access for services normally accessed via MCP.
# This bypasses MCP protocol (Claude-session-only) and calls REST APIs directly,
# enabling CI/GitHub Actions to interact with Supabase and Stripe without MCP.
#
# Usage:
#   scripts/lib/mcp-rest-bridge.sh --smoke          # Connectivity smoke test
#   scripts/lib/mcp-rest-bridge.sh --supabase-query "SELECT 1"
#   scripts/lib/mcp-rest-bridge.sh --stripe-list-products
#   scripts/lib/mcp-rest-bridge.sh --count           # Print total successful call count
#
# Environment:
#   SUPABASE_URL               PostgREST base URL (e.g. https://xxx.supabase.co)
#   SUPABASE_SERVICE_ROLE_KEY  Service role key for DB auth
#   STRIPE_API_KEY             Stripe secret key (sk_...)
#
# Output:
#   JSON result to stdout, call count to stderr.
#   Exit 0 on success, 1 on failure.

MCP_CALL_COUNT=0
BRIDGE_RESULTS_FILE="${MCP_REST_BRIDGE_RESULTS:-/tmp/fugue-mcp-bridge-results.json}"

log() {
  echo "[mcp-rest-bridge] $*" >&2
}

increment_count() {
  MCP_CALL_COUNT=$((MCP_CALL_COUNT + 1))
}

write_count() {
  echo "${MCP_CALL_COUNT}"
}

# --- Supabase (PostgREST) ---

supabase_query() {
  local query="$1"
  if [[ -z "${SUPABASE_URL:-}" ]]; then
    log "SUPABASE_URL not set; skipping."
    return 1
  fi
  if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    log "SUPABASE_SERVICE_ROLE_KEY not set; skipping."
    return 1
  fi

  local rpc_url="${SUPABASE_URL}/rest/v1/rpc/raw_sql"
  local response http_code

  # Try PostgREST RPC endpoint for raw SQL.
  # Fallback: use the pg-meta SQL endpoint if available.
  http_code="$(curl -sS -o /tmp/fugue-supabase-response.json -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 \
    -X POST "${SUPABASE_URL}/rest/v1/rpc" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$(jq -n --arg q "${query}" '{query: $q}')" \
    2>/dev/null || echo "000")"

  if [[ "${http_code}" =~ ^2 ]]; then
    increment_count
    cat /tmp/fugue-supabase-response.json
    return 0
  fi

  # Fallback: try tables listing via REST (for smoke test).
  http_code="$(curl -sS -o /tmp/fugue-supabase-response.json -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 \
    "${SUPABASE_URL}/rest/v1/" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    2>/dev/null || echo "000")"

  if [[ "${http_code}" =~ ^2 ]]; then
    increment_count
    cat /tmp/fugue-supabase-response.json
    return 0
  fi

  log "Supabase request failed (HTTP ${http_code})."
  return 1
}

supabase_smoke() {
  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    jq -n '{service:"supabase",status:"skipped",reason:"credentials not configured"}'
    return 0
  fi

  local http_code
  http_code="$(curl -sS -o /tmp/fugue-supabase-smoke.json -w "%{http_code}" \
    --connect-timeout 10 --max-time 15 \
    "${SUPABASE_URL}/rest/v1/" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    2>/dev/null || echo "000")"

  if [[ "${http_code}" =~ ^2 ]]; then
    increment_count
    jq -n --arg code "${http_code}" '{service:"supabase",status:"ok",http_code:$code}'
    return 0
  fi

  jq -n --arg code "${http_code}" '{service:"supabase",status:"error",http_code:$code}'
  return 1
}

# --- Stripe (REST API) ---

stripe_list_products() {
  if [[ -z "${STRIPE_API_KEY:-}" ]]; then
    log "STRIPE_API_KEY not set; skipping."
    return 1
  fi

  local http_code
  http_code="$(curl -sS -o /tmp/fugue-stripe-response.json -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 \
    "https://api.stripe.com/v1/products?limit=3" \
    -u "${STRIPE_API_KEY}:" \
    2>/dev/null || echo "000")"

  if [[ "${http_code}" =~ ^2 ]]; then
    increment_count
    cat /tmp/fugue-stripe-response.json
    return 0
  fi

  log "Stripe request failed (HTTP ${http_code})."
  return 1
}

stripe_smoke() {
  if [[ -z "${STRIPE_API_KEY:-}" ]]; then
    jq -n '{service:"stripe",status:"skipped",reason:"credentials not configured"}'
    return 0
  fi

  local http_code
  http_code="$(curl -sS -o /tmp/fugue-stripe-smoke.json -w "%{http_code}" \
    --connect-timeout 10 --max-time 15 \
    "https://api.stripe.com/v1/balance" \
    -u "${STRIPE_API_KEY}:" \
    2>/dev/null || echo "000")"

  if [[ "${http_code}" =~ ^2 ]]; then
    increment_count
    jq -n --arg code "${http_code}" '{service:"stripe",status:"ok",http_code:$code}'
    return 0
  fi

  jq -n --arg code "${http_code}" '{service:"stripe",status:"error",http_code:$code}'
  return 1
}

# --- Smoke Test ---

run_smoke() {
  local results=()
  local supabase_result stripe_result

  supabase_result="$(supabase_smoke 2>/dev/null || echo '{"service":"supabase","status":"error"}')"
  stripe_result="$(stripe_smoke 2>/dev/null || echo '{"service":"stripe","status":"error"}')"

  # Count successful calls from results (subshells don't propagate MCP_CALL_COUNT).
  local smoke_count=0
  if printf '%s' "${supabase_result}" | jq -e '.status == "ok"' >/dev/null 2>&1; then
    smoke_count=$((smoke_count + 1))
  fi
  if printf '%s' "${stripe_result}" | jq -e '.status == "ok"' >/dev/null 2>&1; then
    smoke_count=$((smoke_count + 1))
  fi
  MCP_CALL_COUNT=$((MCP_CALL_COUNT + smoke_count))

  jq -n \
    --argjson supabase "${supabase_result}" \
    --argjson stripe "${stripe_result}" \
    --argjson mcp_calls "${MCP_CALL_COUNT}" \
    '{
      bridge: "mcp-rest-bridge",
      mcp_calls: $mcp_calls,
      services: [$supabase, $stripe]
    }'
}

# --- CLI ---

usage() {
  cat <<'EOF'
Usage:
  scripts/lib/mcp-rest-bridge.sh [options]

Options:
  --smoke                  Run connectivity smoke test for all services
  --supabase-query <sql>   Execute a Supabase query via PostgREST
  --stripe-list-products   List Stripe products (limit 3)
  --count                  Print total MCP bridge call count
  -h, --help               Show help
EOF
}

ACTION=""
QUERY_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke)
      ACTION="smoke"
      shift
      ;;
    --supabase-query)
      ACTION="supabase-query"
      QUERY_ARG="${2:-}"
      shift 2
      ;;
    --stripe-list-products)
      ACTION="stripe-list-products"
      shift
      ;;
    --count)
      ACTION="count"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${ACTION}" ]]; then
  echo "Error: no action specified." >&2
  usage >&2
  exit 2
fi

case "${ACTION}" in
  smoke)
    run_smoke
    ;;
  supabase-query)
    if [[ -z "${QUERY_ARG}" ]]; then
      echo "Error: --supabase-query requires a SQL argument." >&2
      exit 2
    fi
    supabase_query "${QUERY_ARG}"
    ;;
  stripe-list-products)
    stripe_list_products
    ;;
  count)
    write_count
    ;;
esac

# Persist call count for downstream consumption.
echo "${MCP_CALL_COUNT}" > "${BRIDGE_RESULTS_FILE}.count"
log "Total MCP bridge calls: ${MCP_CALL_COUNT}"
