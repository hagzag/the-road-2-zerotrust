#!/usr/bin/env bash
# Decode and validate an OIDC ID token against the Keycloak discovery doc.
#
# Usage:  ./decode-token.sh <id_token>
#
# What it checks:
#   - Header  — alg, kid
#   - Payload — iss, aud, exp, iat, nonce (pretty-printed)
#   - Expiration against wall clock
#   - iss matches the Keycloak realm discovery document's "issuer"
#
# It does NOT verify the signature — jwt.io, jose, or `jwt verify` can do
# that. The point here is to understand what the token carries.
set -euo pipefail

KC="${KC:-http://localhost:8081}"
REALM="${REALM:-lab}"

TOKEN="${1:-}"
if [[ -z "$TOKEN" ]]; then
  echo "Usage: $0 <id_token>"
  exit 2
fi

# Base64-URL decode (pad + swap chars)
b64d() {
  local s="$1"
  local pad=$(( 4 - ${#s} % 4 ))
  [[ $pad -eq 4 ]] || s="${s}$(printf '=%.0s' $(seq 1 $pad))"
  echo "$s" | tr '_-' '/+' | base64 -d 2>/dev/null || true
}

IFS='.' read -r H P _ <<<"$TOKEN"

echo "---- Header ----"
b64d "$H" | jq .

echo
echo "---- Payload ----"
PAYLOAD_JSON=$(b64d "$P")
echo "$PAYLOAD_JSON" | jq .

echo
echo "---- Validation ----"
ISS=$(echo "$PAYLOAD_JSON" | jq -r .iss)
EXP=$(echo "$PAYLOAD_JSON" | jq -r .exp)
NOW=$(date +%s)

EXPECTED_ISS=$(curl -fsS "$KC/realms/$REALM/.well-known/openid-configuration" | jq -r .issuer)

if [[ "$ISS" == "$EXPECTED_ISS" ]]; then
  echo "  iss  OK  ($ISS)"
else
  echo "  iss  FAIL  got=$ISS  expected=$EXPECTED_ISS"
fi

if (( EXP > NOW )); then
  echo "  exp  OK  (expires in $((EXP - NOW))s)"
else
  echo "  exp  FAIL  expired $((NOW - EXP))s ago"
fi
