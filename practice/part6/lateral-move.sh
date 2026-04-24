#!/usr/bin/env bash
# The Zero Trust punchline: reachability is not access.
#
# We drop a throwaway busybox pod into the SAME cluster network as the
# protected app. Nothing about k8s stops it from sending packets to
# either the proxy or (worse) straight to demo-app.zt-lab.svc on port 80.
#
# What stops it is the proxy's identity check. The rogue pod has no
# session cookie, no token, no identity. It gets a redirect to the
# Keycloak login page instead of the app's HTML. That's the Policy
# piece of Application/Policy/Tunnel/Route doing its job.
#
# (Also: we hit the raw demo-app service to show that the *network*
# path is wide open. In a real deployment, ZTNA policy is not the only
# control — NetworkPolicy closes this too — but Part 6's point is that
# a ZT proxy alone already flips the exploit story from "lateral to
# the app" to "phish an allowed identity", which is the harder attack.)
set -euo pipefail
NS="zt-lab"

cleanup() { kubectl -n "$NS" delete pod rogue --ignore-not-found --wait=false >/dev/null; }
trap cleanup EXIT

echo "==> Launching rogue pod in namespace '$NS'"
kubectl -n "$NS" run rogue \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --command -- sleep 3600 >/dev/null
kubectl -n "$NS" wait --for=condition=Ready pod/rogue --timeout=60s >/dev/null

echo
echo "==> 1) Rogue pod hitting the proxy (policy enforcement point)"
echo "    Expect: 302 redirect to /oauth2/sign_in -- NOT the app's HTML."
kubectl -n "$NS" exec rogue -- \
  curl -s -o /dev/null -w "HTTP %{http_code}  ->  %{redirect_url}\n" \
  http://oauth2-proxy.zt-lab.svc.cluster.local:4180/

echo
echo "==> 2) Rogue pod bypassing the proxy, hitting demo-app directly"
echo "    This is what lateral movement looks like on a flat network."
echo "    The network path exists. Whether the app is useful without"
echo "    the proxy's X-Auth-Request headers is the application's problem."
kubectl -n "$NS" exec rogue -- \
  curl -s -o /dev/null -w "HTTP %{http_code}  bytes=%{size_download}\n" \
  http://demo-app.zt-lab.svc.cluster.local/

echo
echo "==> Takeaway:"
echo "  - At the proxy: no identity -> 302 to login. Zero Trust wins."
echo "  - At the backend: IP-reachable. In a real cluster you ADD a"
echo "    NetworkPolicy that only allows oauth2-proxy to talk to demo-app."
echo "    Defense in depth: identity at L7, network at L3/L4."
