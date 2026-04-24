#!/usr/bin/env bash
# Part 5 — Keycloak + oauth2-proxy + protected app on k3d.
#
# Brings up the cluster, deploys everything, and auto-bootstraps the realm.
# No manual port-forward needed for setup — only for the browser demo.
set -euo pipefail

CLUSTER="auth-lab"
NS="auth-lab"
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
  python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip("="))' > "$OUT/cookie.secret"
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

echo "==> Applying namespace + Keycloak"
kubectl apply -f "$HERE/manifests/namespace.yaml"
kubectl apply -f "$HERE/manifests/keycloak.yaml"

echo "==> Waiting for Keycloak (this can take ~60s on first boot)"
kubectl -n "$NS" rollout status deploy/postgres --timeout=120s
kubectl -n "$NS" rollout status deploy/keycloak --timeout=240s

echo "==> Rendering oauth2-proxy secret"
kubectl -n "$NS" create secret generic oauth2-proxy \
  --from-literal=OAUTH2_PROXY_CLIENT_ID=my-web-app \
  --from-literal=OAUTH2_PROXY_CLIENT_SECRET="$CLIENT_SECRET" \
  --from-literal=OAUTH2_PROXY_COOKIE_SECRET="$COOKIE_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying demo app + oauth2-proxy"
kubectl apply -f "$HERE/manifests/app.yaml"
kubectl -n "$NS" rollout status deploy/demo-app --timeout=60s
kubectl -n "$NS" rollout status deploy/oauth2-proxy --timeout=60s

echo "==> Bootstrapping Keycloak realm"
"$HERE/bootstrap-realm.sh"

echo
echo "==> Lab ready!"
echo
echo "For browser demo, start port-forwards:"
echo "  kubectl -n $NS port-forward svc/keycloak     8081:8080 &"
echo "  kubectl -n $NS port-forward svc/oauth2-proxy 8080:4180 &"
echo "Then open http://localhost:8080 (login: haggai / Pa55w0rd)"
echo
echo "Keycloak admin:  http://localhost:8081  (admin / Pa55w0rd)"
echo
echo "Run 'task test' to verify all assertions."
