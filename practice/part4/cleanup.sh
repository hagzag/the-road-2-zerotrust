#!/usr/bin/env bash
# Part 4 — tear down.
set -euo pipefail
CLUSTER="wg-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Deleting k3d cluster '$CLUSTER'"
  k3d cluster delete "$CLUSTER"
fi

rm -f "$HERE/wg.pcap"
rm -rf "$HERE/out"
echo "==> Done"
