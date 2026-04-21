#!/usr/bin/env bash
# Part 3 — start capture on the server BEFORE restarting client, so the
# handshake is caught.  30s capture window.
set -euo pipefail
NS="openvpn-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/openvpn.pcap"

echo "==> Starting capture on server sniffer (30s window)"
kubectl -n "$NS" exec deploy/openvpn-server -c sniffer -- \
  timeout 30 tcpdump -i any -s 0 -U -w - 'udp port 1194' > "$OUT" 2>/dev/null &
CAP_PID=$!

echo "==> Restarting client pod to force a fresh handshake"
sleep 1
kubectl -n "$NS" delete pod -l app=openvpn-client --now 2>/dev/null || true

echo "==> Waiting for capture to complete..."
wait $CAP_PID 2>/dev/null || true

BYTES=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null || echo 0)
echo "==> Wrote $OUT ($BYTES bytes)"
echo "==> Classify with: python3 classify.py $OUT"
