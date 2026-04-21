#!/usr/bin/env bash
# Part 4 — bring up a k3d cluster with two WireGuard peers.
set -euo pipefail

CLUSTER="wg-lab"
NS="wg-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
IMAGE="wg-lab:local"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
need docker
need k3d
need kubectl
need wg

mkdir -p "$OUT"

echo "==> Building custom WireGuard image"
docker build -t "$IMAGE" "$HERE"

echo "==> Generating WireGuard keypairs"
for peer in a b; do
  if [[ ! -f "$OUT/peer-${peer}.key" ]]; then
    wg genkey | tee "$OUT/peer-${peer}.key" | wg pubkey > "$OUT/peer-${peer}.pub"
    chmod 600 "$OUT/peer-${peer}.key"
  fi
done

A_PRIV="$(cat "$OUT/peer-a.key")"
A_PUB="$(cat "$OUT/peer-a.pub")"
B_PRIV="$(cat "$OUT/peer-b.key")"
B_PUB="$(cat "$OUT/peer-b.pub")"

echo "==> Rendering wg0.conf for each peer"
cat > "$OUT/wg0-a.conf" <<EOF
[Interface]
PrivateKey = ${A_PRIV}
Address    = 10.99.0.1/24
ListenPort = 51820

[Peer]
PublicKey  = ${B_PUB}
AllowedIPs = 10.99.0.2/32
Endpoint   = peer-b.${NS}.svc.cluster.local:51820
PersistentKeepalive = 25
EOF

cat > "$OUT/wg0-b.conf" <<EOF
[Interface]
PrivateKey = ${B_PRIV}
Address    = 10.99.0.2/24
ListenPort = 51820

[Peer]
PublicKey  = ${A_PUB}
AllowedIPs = 10.99.0.1/32
Endpoint   = peer-a.${NS}.svc.cluster.local:51820
PersistentKeepalive = 25
EOF

echo "==> Creating k3d cluster '$CLUSTER'"
if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  k3d cluster create "$CLUSTER" --wait
fi

echo "==> Importing image into k3d"
k3d image import "$IMAGE" -c "$CLUSTER"

echo "==> Applying namespace"
kubectl apply -f "$HERE/manifests/namespace.yaml"

echo "==> Loading wg0.conf as ConfigMaps"
kubectl -n "$NS" create configmap wg-peer-a-conf \
  --from-file=wg0.conf="$OUT/wg0-a.conf" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap wg-peer-b-conf \
  --from-file=wg0.conf="$OUT/wg0-b.conf" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying Deployments/Services"
kubectl apply -f "$HERE/manifests/wg-peers.yaml"

echo "==> Waiting for pods"
kubectl -n "$NS" rollout status deploy/peer-a --timeout=120s
kubectl -n "$NS" rollout status deploy/peer-b --timeout=120s

echo
echo "==> Up. Try:"
echo "   kubectl exec -n $NS deploy/peer-a -- wg show"
echo "   kubectl exec -n $NS deploy/peer-a -- ping -c3 10.99.0.2"
echo "   task bench     # iperf3 throughput"
echo "   task capture   # capture WireGuard handshake"
echo "   task test      # run assertions"
