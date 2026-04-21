#!/usr/bin/env bash
# Part 3 — bring up OpenVPN server + client in k3d.
set -euo pipefail

CLUSTER="openvpn-lab"
NS="openvpn-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need k3d
need kubectl

mkdir -p "$OUT"

if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Creating k3d cluster '$CLUSTER'"
  k3d cluster create "$CLUSTER" --agents 1
else
  echo "==> k3d cluster '$CLUSTER' exists — reusing"
fi

echo "==> Applying namespace + server manifest"
kubectl apply -f "$HERE/manifests/namespace.yaml"
kubectl apply -f "$HERE/manifests/openvpn-server.yaml"

echo "==> Waiting for server PKI init + rollout"
kubectl -n "$NS" rollout status deploy/openvpn-server --timeout=300s

echo "==> Extracting client.ovpn from server"
for i in {1..30}; do
  if kubectl -n "$NS" exec deploy/openvpn-server -- test -f /etc/openvpn/client.ovpn 2>/dev/null; then
    break
  fi
  echo "  waiting for client.ovpn... ($i)"
  sleep 3
done

kubectl -n "$NS" exec deploy/openvpn-server -- cat /etc/openvpn/client.ovpn > "$OUT/client.ovpn"

echo "==> Ensuring remote points at cluster service"
perl -pi -e 's#^remote .*#remote openvpn-server.openvpn-lab.svc 1194 udp#' "$OUT/client.ovpn"

echo "==> Creating client-ovpn ConfigMap"
kubectl -n "$NS" create configmap client-ovpn \
  --from-file=client.ovpn="$OUT/client.ovpn" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying client manifest"
kubectl apply -f "$HERE/manifests/openvpn-client.yaml"
kubectl -n "$NS" rollout status deploy/openvpn-client --timeout=180s

echo "==> Waiting for tunnel to come up"
for i in {1..30}; do
  if kubectl -n "$NS" logs deploy/openvpn-client -c ovpn-client 2>/dev/null \
       | grep -q "Initialization Sequence Completed"; then
    echo "==> Tunnel up"
    break
  fi
  sleep 2
done

cat <<'EOT'

============================================================
 Tunnel is (or should be) up.
 Next:
   task capture                      # 30s tcpdump -> ./openvpn.pcap
   task classify                     # run DPI classifier on pcap

 Inspect DNS pushes inside the client:
   kubectl -n openvpn-lab exec deploy/openvpn-client -c ovpn-client -- \
     cat /config/client.ovpn | grep dhcp-option

 Cleanup:
   task cleanup
============================================================
EOT
