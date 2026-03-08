#!/usr/bin/env bash
# ============================================================
# TasteTrend Backend Test Script
# ============================================================
# Usage:
#   ./scripts/test_backend.sh search  "What do customers complain about?"
#   ./scripts/test_backend.sh proxy   "Which location has the most complaints?"
#   ./scripts/test_backend.sh api     "What do customers say about staff?"
#   ./scripts/test_backend.sh domain
#
# Required env vars (depending on test mode):
#   AWS_REGION             (default: eu-central-1)
#   SEARCH_LAMBDA_NAME     (for search test)
#   PROXY_LAMBDA_NAME      (for proxy test)
#   API_GATEWAY_URL        (for api test)
#   API_GATEWAY_KEY        (for api test)
#   OPENSEARCH_DOMAIN_NAME (for domain test)
# ============================================================
set -euo pipefail

REGION="${AWS_REGION:-eu-central-1}"

# --- Helpers ---
fmt_json() {
  if command -v jq &>/dev/null; then
    jq .
  else
    cat
  fi
}

usage() {
  cat <<EOF
Usage: $0 <mode> [query]

Modes:
  search  "query"   — Invoke the Search Lambda directly
  proxy   "query"   — Invoke the Proxy Lambda directly
  api     "query"   — Call the public API Gateway /query endpoint
  domain            — Describe the managed OpenSearch domain

Examples:
  $0 search "What do customers complain about in Riverside?"
  $0 proxy  "Which location has the most complaints about waiting times?"
  $0 api    "What do customers say about staff friendliness?"
  $0 domain

Environment variables:
  AWS_REGION             AWS region (default: eu-central-1)
  SEARCH_LAMBDA_NAME     Name of the Search Lambda function
  PROXY_LAMBDA_NAME      Name of the Proxy Lambda function
  API_GATEWAY_URL        Base URL of the API Gateway (e.g. https://xxx.execute-api.eu-central-1.amazonaws.com)
  API_GATEWAY_KEY        API key for the x-api-key header
  OPENSEARCH_DOMAIN_NAME Name of the managed OpenSearch domain
EOF
  exit 1
}

# --- Mode: Search Lambda ---
test_search() {
  local query="$1"
  : "${SEARCH_LAMBDA_NAME:?Set SEARCH_LAMBDA_NAME}"

  echo "=== Search Lambda Test ==="
  echo "Lambda : $SEARCH_LAMBDA_NAME"
  echo "Query  : $query"
  echo ""

  aws lambda invoke \
    --function-name "$SEARCH_LAMBDA_NAME" \
    --region "$REGION" \
    --payload "$(printf '{"query":"%s"}' "$query" | base64)" \
    --cli-binary-format raw-in-base64-out \
    --payload "$(printf '{"query":"%s"}' "$query")" \
    /tmp/tt_search_out.json \
    --output json 2>&1 | fmt_json

  echo ""
  echo "--- Response ---"
  cat /tmp/tt_search_out.json | fmt_json
  rm -f /tmp/tt_search_out.json
}

# --- Mode: Proxy Lambda ---
test_proxy() {
  local query="$1"
  : "${PROXY_LAMBDA_NAME:?Set PROXY_LAMBDA_NAME}"

  echo "=== Proxy Lambda Test ==="
  echo "Lambda : $PROXY_LAMBDA_NAME"
  echo "Query  : $query"
  echo ""

  local payload
  payload=$(printf '{"body":"{\\\"query\\\":\\\"%s\\\"}","headers":{"x-api-key":"%s"}}' "$query" "${API_GATEWAY_KEY:-demo}")

  aws lambda invoke \
    --function-name "$PROXY_LAMBDA_NAME" \
    --region "$REGION" \
    --cli-binary-format raw-in-base64-out \
    --payload "$payload" \
    /tmp/tt_proxy_out.json \
    --output json 2>&1 | fmt_json

  echo ""
  echo "--- Response ---"
  cat /tmp/tt_proxy_out.json | fmt_json
  rm -f /tmp/tt_proxy_out.json
}

# --- Mode: API Gateway ---
test_api() {
  local query="$1"
  : "${API_GATEWAY_URL:?Set API_GATEWAY_URL}"

  echo "=== API Gateway /query Test ==="
  echo "URL    : ${API_GATEWAY_URL}/query"
  echo "Query  : $query"
  echo ""

  local curl_args=(-s -X POST "${API_GATEWAY_URL}/query"
    -H "Content-Type: application/json"
    -d "$(printf '{"query":"%s"}' "$query")")

  if [[ -n "${API_GATEWAY_KEY:-}" ]]; then
    curl_args+=(-H "x-api-key: ${API_GATEWAY_KEY}")
  fi

  curl "${curl_args[@]}" | fmt_json
}

# --- Mode: Domain info ---
test_domain() {
  : "${OPENSEARCH_DOMAIN_NAME:?Set OPENSEARCH_DOMAIN_NAME}"

  echo "=== OpenSearch Domain Info ==="
  echo "Domain : $OPENSEARCH_DOMAIN_NAME"
  echo ""

  aws opensearch describe-domain \
    --domain-name "$OPENSEARCH_DOMAIN_NAME" \
    --region "$REGION" \
    --output json 2>&1 | fmt_json
}

# --- Main ---
[[ $# -lt 1 ]] && usage

MODE="$1"
shift

case "$MODE" in
  search)
    [[ $# -lt 1 ]] && { echo "Error: 'search' mode requires a query argument"; usage; }
    test_search "$1"
    ;;
  proxy)
    [[ $# -lt 1 ]] && { echo "Error: 'proxy' mode requires a query argument"; usage; }
    test_proxy "$1"
    ;;
  api)
    [[ $# -lt 1 ]] && { echo "Error: 'api' mode requires a query argument"; usage; }
    test_api "$1"
    ;;
  domain)
    test_domain
    ;;
  *)
    echo "Unknown mode: $MODE"
    usage
    ;;
esac
