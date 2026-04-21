# Part 2 — SSH Flaws and the Certificate Authority Fix

**Companion lab for**: [SSH and the Cryptographic Turn](https://portfolio.hagzag.com/blog/ssh-and-the-cryptographic-turn/)
**Series**: [The Road to Zero Trust](../../README.md)
**Estimated time**: 15 minutes
**Prereqs**: Docker, [`k3d`](https://k3d.io), `kubectl`, `ssh`, `ssh-keygen`, `ssh-audit` (optional but recommended)

## What you'll see

This lab is structured as a **before → after** narrative that mirrors the blog post:

- **Phase A ("before")** — A legacy bastion with static `authorized_keys`, no CA, no host certs, agent forwarding enabled, and weaker crypto. You'll see every flaw the post describes: TOFU prompts, key sprawl, stale keys, and the agent-forwarding attack surface.
- **Phase B ("after")** — A modern bastion + two internal pods using CA-signed host certs, CA-signed short-lived user certs, `ProxyJump`, and hardened modern crypto. The same reachability, entirely different audit story.

By the end you should be able to answer:

1. Where does the user's identity live in Phase A vs Phase B? (A file vs a signed cert.)
2. What happens in 60 minutes if the laptop is stolen? (Phase A: nothing — the static key works forever. Phase B: the cert expires. No revocation needed.)
3. What do you rotate if the CA is compromised? (The CA key — and the fleet re-trusts a new one with a single ConfigMap update.)
4. Why is agent forwarding dangerous? (Anyone with root on the bastion can use your agent socket.)

## Run it

```bash
# from this directory
./run.sh
```

That script:

1. Builds a custom Alpine sshd image and imports it into k3d.
2. Creates a k3d cluster called `ssh-ca` with NodePorts 2222 (modern) and 2223 (legacy).
3. Generates a fresh CA keypair in `./out/` (local, gitignored).
4. Signs **host certs** for `bastion`, `internal-a`, `internal-b` (valid 30 days).
5. Signs a **user cert** with principal `demo`, valid for **1 hour**.
6. Deploys the legacy bastion (Phase A) with a fat `authorized_keys` file.
7. Deploys the three modern sshd pods (Phase B).
8. Exposes the modern bastion on `localhost:2222`, legacy on `localhost:2223`.
9. Writes a ready-to-use `./out/ssh_config` with both phases.

## Phase A — The Legacy Problem (port 2223)

Connect to the legacy bastion and experience the flaws:

```bash
ssh -F ./out/ssh_config legacy-bastion
```

### Flaw 1: Trust-on-First-Use (TOFU)

On first connection you'll see:

```
The authenticity of host '[127.0.0.1]:2223' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no)?
```

This is TOFU (Trust On First Use) — you're blindly trusting the host key. An attacker intercepting the connection (MITM) gets the same prompt, and you have no way to tell the difference. There's no host certificate, no SSHFP record, no CA signature — just "type yes and pray."

### Flaw 2: Authorized keys sprawl

Once connected, check the key file:

```bash
# Inside legacy-bastion:
cat ~/.ssh/authorized_keys | wc -l
# → 8 keys

cat ~/.ssh/authorized_keys
# → admin@old-laptop-2017, contractor-eng@personal-2020, deploy-bot@ci-2021, ...
```

Eight keys. Who still needs which? When was the last audit? The contractor from 2020 — are they still at the company? Nobody knows. This is the "shadow IAM" the blog post describes: `authorized_keys` files rot faster than anyone audits them.

### Flaw 3: Agent forwarding — the silent leak

The legacy bastion has `AllowAgentForwarding yes`. The dangerous pattern:

```bash
ssh -A -F ./out/ssh_config legacy-bastion
# Now on the bastion, your laptop's agent socket is forwarded:
echo $SSH_AUTH_SOCK
# /tmp/ssh-XXXXXXXX/agent.XXXX
```

If anyone has root on that bastion, they can **use your agent** to authenticate to any host your keys allow — without ever possessing the private key. This is why the blog post recommends `ProxyJump` instead of `-A`. Phase B uses ProxyJump by default.

### Flaw 4: Weaker crypto

Run `ssh-audit` against the legacy bastion:

```bash
ssh-audit -p 2223 127.0.0.1
```

You'll see warnings: older key exchange algorithms, CBC ciphers, no host cert. Compare with the modern bastion audit below.

## Phase B — The Certificate Fix (port 2222)

Now connect the modern way:

```bash
ssh -F ./out/ssh_config bastion
```

### Fix 1: No TOFU — host certs

No prompt. The client verifies the bastion's host cert against the CA public key in `known_hosts`:

```
@cert-authority * ssh-ed25519 AAAA... the-road-2-zerotrust CA
```

Every host cert signed by this CA is automatically trusted. No manual fingerprint verification. No MITM window.

### Fix 2: No authorized_keys — CA-signed user certs

```bash
ssh-keygen -L -f ./out/id_ed25519-cert.pub
```

You'll see:

```
Type: ssh-ed25519-cert-v01@openssh.com user certificate
Signing CA: ED25519 SHA256:... (using ssh-ed25519)
Key ID: "demo@laptop"
Valid: from 2026-04-20T12:00:00 to 2026-04-20T13:00:00
Principals:
    demo
Critical Options: (none)
Extensions:
    permit-pty
```

That single block replaces what used to be 8 lines in `authorized_keys`. And it expires in an hour. If the laptop is stolen, the exposure window is a lunch break — not an incident-response retrospective.

### Fix 3: ProxyJump — no agent forwarding

```bash
ssh -F ./out/ssh_config internal-a    # ProxyJumps via bastion
ssh -F ./out/ssh_config internal-b    # same user cert, different host
```

The `ssh_config` uses `ProxyJump bastion` — the bastion acts as a TCP relay. Your private key never leaves your laptop. The cryptographic handshake is end-to-end from your laptop to the internal host.

### Fix 4: Hardened crypto

```bash
ssh-audit -p 2222 127.0.0.1
```

Modern key exchange (curve25519), AEAD ciphers only (chacha20-poly1305, aes256-gcm), encrypt-then-MAC. Compare the output with the legacy audit on port 2223.

## Inspect the certs

```bash
# User cert (1 hour validity)
ssh-keygen -L -f ./out/id_ed25519-cert.pub

# Host cert (30 day validity)
ssh-keygen -L -f ./out/bastion-host-cert.pub
```

## The audit comparison — side by side

```bash
# Legacy (weaker):
ssh-audit -p 2223 127.0.0.1

# Modern (hardened):
ssh-audit -p 2222 127.0.0.1
```

To deliberately weaken the modern bastion and watch the audit fail:

```bash
kubectl patch configmap sshd-conf-bastion --type merge -p '
data:
  sshd_config: |
    Port 2222
    PasswordAuthentication yes
    KexAlgorithms diffie-hellman-group1-sha1
    Ciphers aes128-cbc,3des-cbc
    TrustedUserCAKeys /etc/ssh/ca-user.pub
    HostKey /etc/ssh/ssh_host_ed25519_key
    HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
'
kubectl rollout restart deploy/bastion
kubectl rollout status deploy/bastion

ssh-audit -p 2222 127.0.0.1   # now shows failing checks
```

Revert with `./run.sh` (idempotent — it'll reset the ConfigMap).

## File layout

```
practice/part2/
├── Dockerfile              Custom Alpine sshd image
├── entrypoint.sh           Simple sshd entrypoint (no s6)
├── README.md
├── Taskfile.yaml
├── run.sh
├── cleanup.sh
├── .gitignore
└── manifests/
    ├── namespace.yaml
    ├── bastion.yaml        Modern CA-based bastion
    ├── internal.yaml       Modern CA-based internal pods
    └── legacy-bastion.yaml Legacy bastion (the "before")
```

`./out/` is created by `run.sh` and holds the CA keypair, host certs, user cert, legacy keys, and a generated `ssh_config`. It is `.gitignore`-d.

## Cleanup

```bash
./cleanup.sh
```

Tears down the cluster and wipes `./out/`. Nothing persists on your laptop.

## Why this matters

Every line in this lab maps to a production control you've probably seen:

| Lab element | Production equivalent |
|-------------|----------------------|
| The CA keypair in `./out/` | An HSM-backed CA operated by Teleport / Smallstep / Vault |
| `TrustedUserCAKeys` in sshd | Fleet-wide config shipped via Puppet / Ansible / a DaemonSet |
| The 1-hour user cert | SSO-gated cert issuance (OIDC → short-lived cert) |
| `@cert-authority` in `known_hosts` | Host certs distributed with the base image |
| `AuthorizedPrincipalsFile` per user | RBAC tied to directory groups |
| Legacy `authorized_keys` (8 stale keys) | Every real bastion you've ever inherited |
| Legacy `AllowAgentForwarding yes` | The `-A` habit that leaks your agent to root |

The lab is small enough to `rm -rf`. The pattern is what runs at scale.

## Takeaway questions

1. What's the **revocation** story if a signed cert leaks? (Hint: there's `RevokedKeys`, but the canonical answer is *short validity*.)
2. Why is `AuthorizedPrincipalsFile` more auditable than `authorized_keys`? (Identity → role → host, not identity → host.)
3. What's still missing before this is production-ready? (MFA at cert issuance, SSO-bound principals, host-cert rotation cron, revocation list distribution.)
4. Why does agent forwarding still exist if ProxyJump is strictly better? (Backward compatibility — but new deployments should default to ProxyJump.)

## Next

→ [Part 3 — VPNs: OpenVPN, IPsec, and the TLS Tunnel](../part3/)

← [Part 1 — From Trusted Wires to the Open Internet](../part1/)
