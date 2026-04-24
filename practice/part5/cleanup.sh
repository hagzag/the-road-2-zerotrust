#!/usr/bin/env bash
# Part 5 — tear down.
set -euo pipefail
CLUSTER="auth-lab"
HERE="$(cd "$(dirname "$0")" && pwd)"

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Deleting k3d cluster '$CLUSTER'"
  k3d cluster delete "$CLUSTER"
fi

rm -rf "$HERE/out"
echo "==> Done"
