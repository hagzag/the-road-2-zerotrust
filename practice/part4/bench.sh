#!/usr/bin/env bash
# iperf3 through the WG tunnel vs. pod-to-pod control.
set -euo pipefail

NS="wg-lab"

echo "==> Starting iperf3 server on peer-a"
kubectl -n "$NS" exec deploy/peer-a -- sh -c 'pkill iperf3 2>/dev/null || true; nohup iperf3 -s -1 >/dev/null 2>&1 &'
sleep 2

echo
echo "==> Control (direct pod IP, no tunnel)"
PEER_A_IP=$(kubectl -n "$NS" get pod -l app=peer-a -o jsonpath='{.items[0].status.podIP}')
kubectl -n "$NS" exec deploy/peer-b -- iperf3 -c "$PEER_A_IP" -t 5 -f m | tail -n 4

echo
echo "==> Restarting iperf3 server on peer-a"
kubectl -n "$NS" exec deploy/peer-a -- sh -c 'pkill iperf3 2>/dev/null || true; nohup iperf3 -s -1 >/dev/null 2>&1 &'
sleep 2

echo
echo "==> Through WG tunnel (10.99.0.1)"
kubectl -n "$NS" exec deploy/peer-b -- iperf3 -c 10.99.0.1 -t 5 -f m | tail -n 4

echo
echo "==> Done. Compare the two bitrates — the difference is WG overhead."
