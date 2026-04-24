#!/usr/bin/env bash
# Part 6 — Zero Trust Networking lab on k3d.
#
# Brings up a k3d cluster, Keycloak, and an identity-aware proxy
# (oauth2-proxy) gating a plain nginx backend. The proxy enforces an
# email allowlist so one seeded user gets in and the other is denied
# even after a successful Keycloak login.
#
# Run `./bootstrap-realm.sh` after this to create the realm, client,
# and two users. Run `./lateral-move.sh` to see a rogue pod hit the
# network but fail at policy.
set -euo pipefail

CLUSTER="zt-lab"
NS="zt-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
need docker
need k3d
need kubectl
need jq

mkdir -p "$OUT"

echo "==> Generating oauth2-proxy secrets"
if [[ ! -f "$OUT/cookie.secret" ]]; then
  head -c 32 /dev/urandom | base64 | tr -d '\n' > "$OUT/cookie.secret"
fi
if [[ ! -f "$OUT/client.secret" ]]; then
  head -c 24 /dev/urandom | base64 | tr -d '\n=' > "$OUT/client.secret"
fi
COOKIE_SECRET="$(cat "$OUT/cookie.secret")"
CLIENT_SECRET="$(cat "$OUT/client.secret")"

echo "==> Creating k3d cluster '$CLUSTER'"
if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  k3d cluster create "$CLUSTER" --wait
fi
kubectl config use-context "k3d-$CLUSTER"

echo "==> Applying namespace + Keycloak"
kubectl apply -f "$HERE/manifests/namespace.yaml"
kubectl apply -f "$HERE/manifests/keycloak.yaml"

echo "==> Waiting for Keycloak (this can take ~60s on first boot)"
kubectl -n "$NS" rollout status deploy/postgres --timeout=120s
kubectl -n "$NS" rollout status deploy/keycloak --timeout=240s

echo "==> Rendering oauth2-proxy secret"
kubectl -n "$NS" create secret generic oauth2-proxy \
  --from-literal=OAUTH2_PROXY_CLIENT_ID=zt-web-app \
  --from-literal=OAUTH2_PROXY_CLIENT_SECRET="$CLIENT_SECRET" \
  --from-literal=OAUTH2_PROXY_COOKIE_SECRET="$COOKIE_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying demo app + oauth2-proxy + allowlist"
kubectl apply -f "$HERE/manifests/app.yaml"
kubectl -n "$NS" rollout status deploy/demo-app --timeout=60s
kubectl -n "$NS" rollout status deploy/oauth2-proxy --timeout=60s

echo "$CLIENT_SECRET" > "$OUT/client.secret"

echo
echo "==> Next:"
echo "  1. kubectl -n $NS port-forward svc/keycloak     8081:8080"
echo "  2. kubectl -n $NS port-forward svc/oauth2-proxy 8080:4180"
echo "  3. ./bootstrap-realm.sh"
echo "  4. open http://localhost:8080"
echo "       alice@example.com / Pa55w0rd  -> gets in"
echo "       bob@example.com   / Pa55w0rd  -> authenticated by Keycloak,"
echo "                                        then denied by oauth2-proxy"
echo
echo "Then: ./lateral-move.sh  (rogue pod hits the network, fails at policy)"
echo
echo "Keycloak admin:  http://localhost:8081  (admin / Pa55w0rd)"
