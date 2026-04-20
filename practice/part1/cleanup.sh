#!/usr/bin/env bash
# Part 1 — tear down the lab cluster.
set -euo pipefail
CLUSTER="trusted-wire"

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Deleting k3d cluster '$CLUSTER'"
  k3d cluster delete "$CLUSTER"
else
  echo "==> No cluster '$CLUSTER' to delete"
fi

rm -f ./telnet.pcap || true
echo "==> Done"
