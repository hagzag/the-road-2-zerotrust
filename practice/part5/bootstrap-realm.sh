#!/usr/bin/env bash
# Bootstrap a Keycloak realm + OIDC client + demo user using kcadm.sh
# (Keycloak's built-in admin CLI). Runs all commands inside the Keycloak
# pod via a single kubectl exec session so the kcadm config persists.
# Idempotent — safe to re-run.
set -euo pipefail

NS="auth-lab"
REALM="lab"
CLIENT_ID="my-web-app"
USER="haggai"
PASS="Pa55w0rd"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"

CLIENT_SECRET="$(cat "$OUT/client.secret")"

echo "==> Waiting for Keycloak to be ready"
for i in {1..60}; do
  if kubectl -n "$NS" exec deploy/keycloak -- /bin/sh -c "echo > /dev/tcp/localhost/8080" 2>/dev/null; then
    sleep 5
    break
  fi
  echo "  waiting... ($i)"
  sleep 3
done

echo "==> Bootstrapping realm, client, and user via kcadm.sh"
kubectl -n "$NS" exec deploy/keycloak -- /bin/sh -c '
set -e
KCADM="/opt/keycloak/bin/kcadm.sh"
CONFIG="--config /tmp/kcadm.config"
REALM="lab"
CLIENT_ID="my-web-app"
CLIENT_SECRET="'"$CLIENT_SECRET"'"
USER="haggai"
PASS="Pa55w0rd"

echo "  ==> Logging in"
$KCADM config credentials --server http://localhost:8080 --realm master --user admin --password Pa55w0rd $CONFIG

echo "  ==> Ensuring realm $REALM"
if $KCADM get realms/$REALM $CONFIG 2>/dev/null | grep -q "\"realm\""; then
  echo "  realm already exists"
else
  $KCADM create realms -s realm=$REALM -s enabled=true $CONFIG
fi

echo "  ==> Ensuring client $CLIENT_ID"
EXISTING=$($KCADM get clients -r $REALM --fields id,clientId --format csv $CONFIG 2>/dev/null | grep "$CLIENT_ID" | cut -d, -f1 | tr -d \" || true)
if [ -n "$EXISTING" ]; then
  echo "  updating existing client $EXISTING"
  $KCADM update clients/$EXISTING -r $REALM $CONFIG \
    -s clientId=$CLIENT_ID \
    -s enabled=true \
    -s publicClient=false \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=false \
    -s "redirectUris=[\"http://localhost:8080/oauth2/callback\"]" \
    -s "webOrigins=[\"http://localhost:8080\"]" \
    -s secret=$CLIENT_SECRET
else
  $KCADM create clients -r $REALM $CONFIG \
    -s clientId=$CLIENT_ID \
    -s enabled=true \
    -s publicClient=false \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=false \
    -s "redirectUris=[\"http://localhost:8080/oauth2/callback\"]" \
    -s "webOrigins=[\"http://localhost:8080\"]" \
    -s secret=$CLIENT_SECRET
fi

echo "  ==> Ensuring user $USER"
EXISTING_USER=$($KCADM get users -r $REALM --fields id,username --format csv $CONFIG 2>/dev/null | grep "$USER" | cut -d, -f1 | tr -d \" || true)
if [ -n "$EXISTING_USER" ]; then
  echo "  user already exists"
else
  $KCADM create users -r $REALM $CONFIG \
    -s username=$USER \
    -s enabled=true \
    -s emailVerified=true \
    -s email="haggai@example.com" \
    -s firstName="Haggai" \
    -s lastName="Zagury"
fi

echo "  ==> Setting user password"
$KCADM set-password -r $REALM --username $USER --new-password $PASS $CONFIG
'

echo "$REALM:$CLIENT_ID:$USER" > "$OUT/realm-bootstrapped"

echo
echo "==> Realm bootstrapped."
echo "  Realm:       $REALM"
echo "  Client ID:   $CLIENT_ID"
echo "  User:        $USER / $PASS"
echo
echo "For browser demo, start port-forwards:"
echo "  kubectl -n $NS port-forward svc/keycloak     8081:8080 &"
echo "  kubectl -n $NS port-forward svc/oauth2-proxy 8080:4180 &"
echo "Then open http://localhost:8080"
