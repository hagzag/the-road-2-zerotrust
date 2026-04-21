#!/usr/bin/env bash
# Part 2 — tear down.
set -euo pipefail
CLUSTER="ssh-ca"
HERE="$(cd "$(dirname "$0")" && pwd)"

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Deleting k3d cluster '$CLUSTER'"
  k3d cluster delete "$CLUSTER"
fi

echo "==> Removing generated CA / host keys / certs in ./out"
rm -rf "$HERE/out"
echo "==> Done"
