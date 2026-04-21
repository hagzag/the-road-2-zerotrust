#!/bin/bash
# Bring up WireGuard from /wg/wg0.conf (ConfigMap mount).
# Parses the ini-style config and uses iproute2 + wg commands directly
# — no wg-quick (which needs resolvconf, etc.).
set -euo pipefail

CONF="/wg/wg0.conf"
if [ ! -f "$CONF" ]; then
  echo "FATAL: $CONF not found" >&2; exit 1
fi

parse_conf() {
  awk -v section="$1" -v key="$2" '
    $0 ~ /^\[/ { current = $0; next }
    current == "[" section "]" && $1 == key { print $3; exit }
  ' "$CONF"
}

parse_peers() {
  awk '
    /^\[Interface\]/{ if (pub) { print pub,ips,ep,ka; pub=""; ips=""; ep=""; ka="" } next }
    /^\[Peer\]/{ next }
    $1=="PublicKey"{pub=$3}
    $1=="AllowedIPs"{ips=$3}
    $1=="Endpoint"{ep=$3}
    $1=="PersistentKeepalive"{ka=$3}
    END{ if (pub) print pub,ips,ep,ka }
  ' "$CONF"
}

PRIVKEY=$(parse_conf Interface PrivateKey)
ADDRESS=$(parse_conf Interface Address)
LISTEN_PORT=$(parse_conf Interface ListenPort)

if [ -z "$PRIVKEY" ] || [ -z "$ADDRESS" ]; then
  echo "FATAL: missing PrivateKey or Address in [Interface]" >&2; exit 1
fi

PORT="${LISTEN_PORT:-51820}"

echo "==> Creating wg0 interface"
ip link add dev wg0 type wireguard

echo "==> Configuring wg0 (port $PORT)"
wg set wg0 private-key <(echo "$PRIVKEY") listen-port "$PORT"

while IFS=' ' read -r pub ips ep ka; do
  echo "==> Adding peer $pub (allowed: $ips, endpoint: ${ep:-none})"
  ARGS="peer $pub allowed-ips $ips"
  [ -n "$ep" ] && ARGS="$ARGS endpoint $ep"
  [ -n "$ka" ] && ARGS="$ARGS persistent-keepalive $ka"
  wg set wg0 $ARGS
done < <(parse_peers)

echo "==> Assigning address $ADDRESS"
ip addr add dev wg0 "$ADDRESS"

echo "==> Bringing wg0 up"
ip link set wg0 up

echo "==> WireGuard interface wg0 is up"
wg show wg0

echo "==> Ready — sleeping forever"
exec sleep infinity
