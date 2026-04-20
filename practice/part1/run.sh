#!/usr/bin/env bash
# Part 1 — one-shot runner for the trusted-wire lab.
# Spins up a k3d cluster, deploys the telnetd+sniffer Pod, and prints
# the commands you need to run by hand to capture your own password.
set -euo pipefail

CLUSTER="trusted-wire"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need k3d
need kubectl

if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Creating k3d cluster '$CLUSTER'"
  k3d cluster create "$CLUSTER" --agents 1
else
  echo "==> k3d cluster '$CLUSTER' already exists — reusing"
fi

echo "==> Applying telnet-demo manifest"
kubectl apply -f "$(dirname "$0")/telnet-demo.yaml"

echo "==> Waiting for Pod to be Ready"
kubectl wait --for=condition=Ready pod/telnet-demo --timeout=90s

cat <<'EOT'

============================================================
 Pod is up. To walk the lab:

 1) In another terminal, telnet in:
      kubectl exec -it telnet-demo -c client -- \
        sh -c "telnet 127.0.0.1 23"
      login:    demo
      password: demo
      # type a few commands, then exit

 2) Stop the capture and pull the pcap:
      kubectl exec telnet-demo -c sniffer -- pkill -INT tcpdump || true
      kubectl cp telnet-demo:/tmp/cap/telnet.pcap ./telnet.pcap -c sniffer

 3) Read your own password in ASCII:
      wireshark ./telnet.pcap
      # or, no GUI:
      tshark -r ./telnet.pcap -q -z follow,tcp,ascii,0

 4) Clean up:
      ./cleanup.sh
============================================================
EOT
