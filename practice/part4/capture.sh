#!/usr/bin/env bash
# Capture 20s of UDP/51820 on peer-a and pull the pcap out.
# Starts capture BEFORE bouncing the interface to catch the handshake.
set -euo pipefail

NS="wg-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"
PCAP="$HERE/wg.pcap"

echo "==> Starting 20s capture on peer-a, UDP/51820 (background)"
kubectl -n "$NS" exec deploy/peer-a -- sh -c \
  'tcpdump -i any -s0 -w /tmp/wg.pcap "udp port 51820" >/dev/null 2>&1 &
   TCPDUMP_PID=$!
   echo $TCPDUMP_PID > /tmp/tcpdump.pid' 2>/dev/null || true

sleep 2

echo "==> Forcing handshake from peer-b (down/up wg0)"
kubectl -n "$NS" exec deploy/peer-b -- sh -c \
  'ip link set wg0 down; ip link set wg0 up; wg set wg0 peer $(wg show wg0 peers | head -1 | awk "{print \$2}") persistent-keepalive 5' 2>/dev/null || \
kubectl -n "$NS" exec deploy/peer-b -- sh -c \
  'ip link set wg0 down 2>/dev/null; ip link set wg0 up 2>/dev/null' || true

sleep 2

kubectl -n "$NS" exec deploy/peer-b -- ping -c3 -W2 10.99.0.1 >/dev/null 2>&1 || true

echo "==> Waiting for capture window"
sleep 16

echo "==> Stopping tcpdump and pulling pcap"
kubectl -n "$NS" exec deploy/peer-a -- sh -c 'kill $(cat /tmp/tcpdump.pid) 2>/dev/null; sleep 1' 2>/dev/null || true

kubectl -n "$NS" cp "$(kubectl -n "$NS" get pod -l app=peer-a -o jsonpath='{.items[0].metadata.name}'):tmp/wg.pcap" "$PCAP" 2>/dev/null || {
  kubectl -n "$NS" exec deploy/peer-a -- cat /tmp/wg.pcap > "$PCAP"
}

BYTES=$(stat -f%z "$PCAP" 2>/dev/null || stat -c%s "$PCAP" 2>/dev/null || echo 0)
echo "==> Wrote $PCAP ($BYTES bytes)"
echo "   Open with: wireshark $PCAP"
echo "   Filter: udp.port == 51820"
echo "   Look for the 148-byte initiator handshake and 92-byte responder."
