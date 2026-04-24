#!/usr/bin/env bash
# Bootstrap a Keycloak realm, OIDC client, and two demo users.
# Idempotent — safe to re-run.
#
# Assumes `kubectl port-forward svc/keycloak 8081:8080` is running.
#
# alice@example.com -> on the allowlist, gets in
# bob@example.com   -> NOT on the allowlist; Keycloak authenticates her,
#                      oauth2-proxy denies her at policy. This is the
#                      Zero Trust enforcement point.
set -euo pipefail

KC="http://localhost:8081"
REALM="zt"
CLIENT_ID="zt-web-app"
PASS="Pa55w0rd"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"

CLIENT_SECRET="$(cat "$OUT/client.secret")"

echo "==> Waiting for Keycloak on $KC"
until curl -fsS -o /dev/null "$KC/realms/master"; do sleep 2; done

echo "==> Getting admin token"
ADMIN_TOKEN="$(curl -fsS \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=Pa55w0rd" \
  -d "grant_type=password" \
  "$KC/realms/master/protocol/openid-connect/token" | jq -r .access_token)"

auth() { curl -fsS -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" "$@"; }

echo "==> Ensuring realm '$REALM'"
if ! auth "$KC/admin/realms/$REALM" >/dev/null 2>&1; then
  auth -X POST "$KC/admin/realms" -d "$(jq -n --arg r "$REALM" '{realm:$r, enabled:true}')"
fi

echo "==> Ensuring client '$CLIENT_ID'"
EXISTING="$(auth "$KC/admin/realms/$REALM/clients?clientId=$CLIENT_ID" | jq -r '.[0].id // empty')"
CLIENT_JSON=$(jq -n --arg cid "$CLIENT_ID" --arg sec "$CLIENT_SECRET" '{
  clientId: $cid,
  enabled: true,
  protocol: "openid-connect",
  publicClient: false,
  standardFlowEnabled: true,
  directAccessGrantsEnabled: false,
  serviceAccountsEnabled: false,
  redirectUris: ["http://localhost:8080/oauth2/callback"],
  webOrigins: ["http://localhost:8080"],
  secret: $sec,
  attributes: { "pkce.code.challenge.method": "S256" }
}')
if [[ -z "$EXISTING" ]]; then
  auth -X POST "$KC/admin/realms/$REALM/clients" -d "$CLIENT_JSON" >/dev/null
else
  auth -X PUT  "$KC/admin/realms/$REALM/clients/$EXISTING" -d "$CLIENT_JSON"
fi

ensure_user() {
  local username="$1" email="$2" first="$3" last="$4"
  echo "==> Ensuring user '$username' ($email)"
  local uid
  uid="$(auth "$KC/admin/realms/$REALM/users?username=$username" | jq -r '.[0].id // empty')"
  local ujson
  ujson=$(jq -n \
    --arg u "$username" --arg e "$email" \
    --arg f "$first"    --arg l "$last" '{
      username: $u, enabled: true, emailVerified: true,
      email: $e, firstName: $f, lastName: $l
    }')
  if [[ -z "$uid" ]]; then
    auth -X POST "$KC/admin/realms/$REALM/users" -d "$ujson"
    uid="$(auth "$KC/admin/realms/$REALM/users?username=$username" | jq -r '.[0].id')"
  fi
  auth -X PUT "$KC/admin/realms/$REALM/users/$uid/reset-password" \
    -d "$(jq -n --arg p "$PASS" '{type:"password", value:$p, temporary:false}')"
}

ensure_user alice alice@example.com Alice Allowed
ensure_user bob   bob@example.com   Bob   Denied

echo
echo "==> Done."
echo "  Realm:       $REALM"
echo "  Client ID:   $CLIENT_ID"
echo "  Allowed:     alice@example.com / $PASS  (passes allowlist)"
echo "  Denied:      bob@example.com   / $PASS  (authenticated, denied at proxy)"
echo "  Discovery:   $KC/realms/$REALM/.well-known/openid-configuration"
echo
echo "Open http://localhost:8080 and log in as each to see the difference."
