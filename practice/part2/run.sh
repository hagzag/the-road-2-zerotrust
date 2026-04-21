#!/usr/bin/env bash
# Part 2 — one-shot: legacy SSH flaws + SSH CA + bastion + 2 internal pods + user cert.
# Phase A: legacy-bastion with authorized_keys sprawl (port 2223)
# Phase B: modern CA-signed setup with ProxyJump (port 2222)
set -euo pipefail

CLUSTER="ssh-ca"
NS="ssh-ca"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
IMAGE="ssh-ca-sshd:latest"

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need k3d
need kubectl
need ssh-keygen
need docker

mkdir -p "$OUT"

# --- Build custom sshd image -----------------------------------------------
echo "==> Building custom sshd image: $IMAGE"
docker build -t "$IMAGE" "$HERE"

# --- Cluster ---------------------------------------------------------------
if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  echo "==> Creating k3d cluster '$CLUSTER' with NodePorts 2222+2223"
  k3d cluster create "$CLUSTER" --agents 1 \
    -p "2222:32222@loadbalancer" \
    -p "2223:32223@loadbalancer"
else
  echo "==> k3d cluster '$CLUSTER' exists — reusing"
fi

echo "==> Importing image into k3d"
k3d image import "$IMAGE" --cluster "$CLUSTER"

kubectl apply -f "$HERE/manifests/namespace.yaml"

# --- CA key (idempotent) ---------------------------------------------------
if [[ ! -f "$OUT/ca-user" ]]; then
  echo "==> Generating SSH CA keypair"
  ssh-keygen -t ed25519 -N "" -C "the-road-2-zerotrust CA" -f "$OUT/ca-user"
fi

# --- Host keys + host certs (one per pod) ----------------------------------
# Bastion cert includes 127.0.0.1 because the client connects via localhost.
# Internal cert includes the in-cluster DNS name for ProxyJump resolution.
sign_host() {
  local name="$1"
  shift
  local principals="$name,$name.$NS.svc"
  # Extra principals (e.g. 127.0.0.1 for the externally-exposed bastion)
  for extra in "$@"; do
    principals="$principals,$extra"
  done
  if [[ ! -f "$OUT/$name-host" ]]; then
    ssh-keygen -t ed25519 -N "" -C "$name host key" -f "$OUT/$name-host"
  fi
  ssh-keygen -s "$OUT/ca-user" -I "$name-host" -h -n "$principals" -V +30d \
    "$OUT/$name-host.pub" >/dev/null
}
sign_host bastion 127.0.0.1
sign_host internal-a
sign_host internal-b

# --- Legacy bastion host key (no cert — TOFU!) -----------------------------
if [[ ! -f "$OUT/legacy-bastion-host" ]]; then
  echo "==> Generating legacy bastion host key (no cert — pure TOFU)"
  ssh-keygen -t ed25519 -N "" -C "legacy-bastion host key" -f "$OUT/legacy-bastion-host"
fi

# --- Legacy user key (plain, no cert — static authorized_keys) ------------
if [[ ! -f "$OUT/legacy_id_ed25519" ]]; then
  echo "==> Generating legacy user key (no cert — goes into authorized_keys)"
  ssh-keygen -t ed25519 -N "" -C "demo@laptop-legacy" -f "$OUT/legacy_id_ed25519"
fi

# --- User cert (1h) --------------------------------------------------------
if [[ ! -f "$OUT/id_ed25519" ]]; then
  ssh-keygen -t ed25519 -N "" -C "demo@laptop" -f "$OUT/id_ed25519"
fi
ssh-keygen -s "$OUT/ca-user" -I "demo@laptop" -n demo -V +1h "$OUT/id_ed25519.pub" >/dev/null

# --- Ship CA + host keys/certs to cluster ----------------------------------
echo "==> Installing CA public key + host keys/certs as k8s Secrets"
kubectl -n "$NS" create secret generic ssh-ca-pub \
  --from-file=ca-user.pub="$OUT/ca-user.pub" \
  --dry-run=client -o yaml | kubectl apply -f -

for name in bastion internal-a internal-b; do
  kubectl -n "$NS" create secret generic "$name-host-key" \
    --from-file=ssh_host_ed25519_key="$OUT/$name-host" \
    --from-file=ssh_host_ed25519_key.pub="$OUT/$name-host.pub" \
    --from-file=ssh_host_ed25519_key-cert.pub="$OUT/$name-host-cert.pub" \
    --dry-run=client -o yaml | kubectl apply -f -
done

# --- Legacy bastion secrets ------------------------------------------------
kubectl -n "$NS" create secret generic legacy-bastion-host-key \
  --from-file=ssh_host_ed25519_key="$OUT/legacy-bastion-host" \
  --from-file=ssh_host_ed25519_key.pub="$OUT/legacy-bastion-host.pub" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Deploy all pods (manifests first, then overlay ConfigMaps) ------------
echo "==> Deploying legacy bastion + modern CA-based pods"
kubectl apply -f "$HERE/manifests/legacy-bastion.yaml"
kubectl apply -f "$HERE/manifests/bastion.yaml"
kubectl apply -f "$HERE/manifests/internal.yaml"

# Now overlay the authorized_keys ConfigMap with the real legacy key
# (must come AFTER the manifest apply so it takes precedence)
REAL_LEGACY_KEY=$(cat "$OUT/legacy_id_ed25519.pub")
kubectl -n "$NS" create configmap legacy-authorized-keys \
  --from-literal=authorized_keys="$REAL_LEGACY_KEY
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... admin@old-laptop-2017
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... admin@old-laptop-2017-deploy
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... contractor-eng@personal-2020
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... deploy-bot@ci-2021
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... sre-lead@workstation-2020
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... contractor-qa@laptop-2022
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... automate@ansible-tower-2021
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... old-admin@backup-server-2019" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart legacy-bastion to pick up the corrected ConfigMap
kubectl -n "$NS" rollout restart deploy/legacy-bastion

echo "==> Waiting for rollouts"
kubectl -n "$NS" rollout status deploy/legacy-bastion --timeout=120s
kubectl -n "$NS" rollout status deploy/bastion     --timeout=120s
kubectl -n "$NS" rollout status deploy/internal-a  --timeout=120s
kubectl -n "$NS" rollout status deploy/internal-b  --timeout=120s

# --- Generate client-side ssh_config ---------------------------------------
cat > "$OUT/ssh_config" <<EOF
# Generated by practice/part2/run.sh
#
# --- PHASE A: Legacy (barebone) SSH ---
# This is the "before" picture: static keys, TOFU, agent forwarding risk.
Host legacy-bastion
    HostName 127.0.0.1
    Port 2223
    User demo
    IdentityFile $OUT/legacy_id_ed25519
    IdentitiesOnly yes
    UserKnownHostsFile $OUT/legacy_known_hosts
    StrictHostKeyChecking accept-new

# --- PHASE B: Modern (cert-based) SSH ---
# This is the "after" picture: CA-signed certs, ProxyJump, no agent forwarding.
Host bastion
    HostName 127.0.0.1
    Port 2222
    User demo
    IdentityFile $OUT/id_ed25519
    CertificateFile $OUT/id_ed25519-cert.pub
    IdentitiesOnly yes
    UserKnownHostsFile $OUT/known_hosts
    StrictHostKeyChecking yes

Host internal-a internal-b
    HostName %h.$NS.svc
    Port 2222
    User demo
    IdentityFile $OUT/id_ed25519
    CertificateFile $OUT/id_ed25519-cert.pub
    IdentitiesOnly yes
    ProxyJump bastion
    UserKnownHostsFile $OUT/known_hosts
    StrictHostKeyChecking yes
EOF

# --- Generate known_hosts for CA-trusted hosts -----------------------------
cat > "$OUT/known_hosts" <<EOF
@cert-authority * $(cat "$OUT/ca-user.pub")
EOF

# --- Done ------------------------------------------------------------------
cat <<EOF

============================================================
 Part 2 — SSH Flaws & Certificates lab is ready.

 PHASE A — Legacy SSH (the problem):
   ssh -F $OUT/ssh_config legacy-bastion
   # → TOFU (Trust On First Use) prompt, static key, agent forwarding enabled

 PHASE B — Cert-based SSH (the fix):
   ssh -F $OUT/ssh_config bastion
   ssh -F $OUT/ssh_config internal-a
   ssh -F $OUT/ssh_config internal-b
   # → No TOFU, ProxyJump, 1-hour cert expiry

 Inspect the user cert:
   ssh-keygen -L -f $OUT/id_ed25519-cert.pub

 Audit the hardened bastion:
   ssh-audit -p 2222 127.0.0.1

 Audit the legacy bastion (weaker crypto):
   ssh-audit -p 2223 127.0.0.1

 Cleanup:
   ./cleanup.sh
============================================================
EOF
