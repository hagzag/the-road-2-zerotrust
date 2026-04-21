#!/usr/bin/env bash
# Part 3 — tear down.
set -euo pipefail
CLUSTER="openvpn-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Deleting k3d cluster '$CLUSTER'"
  k3d cluster delete "$CLUSTER"
fi

rm -f "$HERE/openvpn.pcap"
rm -rf "$HERE/out"
echo "==> Done"
