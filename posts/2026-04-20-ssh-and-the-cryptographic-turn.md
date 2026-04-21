---
title: "SSH and the Cryptographic Turn"
meta_title: "SSH and the Cryptographic Turn — Remote Access, Part 2"
description: "SSH replaced telnet in a few years and still runs everything three decades later. Here's why 'SSH is solved' is the most dangerous sentence in your runbook."
date: 2026-04-20T10:00:00+00:00
image: "/images/blog/2026/ssh-and-the-cryptographic-turn/cover.png"
categories:
  - "DevOps"
  - "Security"
tags:
  - "ssh"
  - "remote-access"
  - "zero-trust"
  - "certificates"
  - "bastion"
  - "openssh"
  - "kubernetes"
  - "k3d"
draft: false
author: "Haggai Philip Zagury"
medium_url: ""
---

## TL;DR

SSH replaced telnet almost overnight and has held the line for three decades. That's the good news. The bad news is that "SSH is solved" is the most dangerous sentence in your runbook: static keys proliferate into the thousands, `authorized_keys` files rot faster than anyone audits them, and at fleet scale the bastion becomes its own attack surface. The ~2015 answer — short-lived certificates signed by a CA you control — is still the right answer in 2026. This is Part 2 of a seven-part series; [Part 1 started at telnet](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28), Part 2 is the cryptographic turn that replaced it.

> *This post is a written, expanded version of a module I've taught for years inside my private KubeExperience workshops and referenced in talks. If you've heard me say "static SSH keys are technical debt you're paying in breach-probability," this is the permanent reference for that argument.*

## The key you forgot you had

A few years back I joined a new client for a platform-engineering engagement, did the usual onboarding, and got added to a shared bastion host. Out of habit, I ran `ssh-add -l` on the bastion to check which keys were cached. One of them — a 2,048-bit RSA key with a comment in the format `firstname@old-laptop-2017` — was mine. It had been cached there for years, survived two laptop replacements, a full OS reinstall, and three job changes.

Nobody did anything wrong. The key just… stayed. That is the SSH story in miniature: a protocol that works beautifully for the first ten hosts you deploy and silently becomes the world's largest shadow IAM system by the time you have ten thousand.

[IMAGE_PROMPT: Before/after diagram. Left: a laptop with a tangle of colored strings running to dozens of servers, each string labeled with a key filename like "id_rsa_old", "deploy_key_prod", "backup_2019". Right: the same laptop with a single thick line to a "CA" box, and short thin lines from the CA box to the servers, each marked with a ticking timer. Caption: "static keys vs. short-lived certificates — same reachability, very different audit story."]

## SSH in one paragraph, then we move on

Because you already know this: SSH is an L7 protocol riding on L4 TCP (port 22 by convention). Client and server do a Diffie-Hellman handshake to agree on a symmetric session key, then authenticate with either passwords (don't), public keys (mostly), or signed certificates (what we'll end up recommending). Everything above the handshake — your commands, your `scp`, your port-forwarded Redis — runs inside that encrypted channel. That's the whole thing. Every complication in the rest of this post is something we've bolted on top of those basics because the trust boundary kept moving.

If [Part 1 was about the physical wire being the boundary](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28), Part 2 is about the *host* becoming it. SSH doesn't care who's in the room with you. It cares whether you have a key the server's `authorized_keys` file recognizes.

## Pick your keys like you mean it

The short version, in 2026:

- **ed25519 by default.** Smaller, faster, and no one has found a reason to doubt the curve in the decade-plus it's been in OpenSSH. Generate with `ssh-keygen -t ed25519 -C "you@laptop-$(date +%Y)"` and move on.
- **RSA 3072+ as a compatibility fallback** for the handful of ancient bastions that still don't accept ed25519. 2,048 is no longer a defensible default.
- **ECDSA** only if you really care about NIST-suite compliance; otherwise skip it — the nonce-reuse failure mode is not one you want your team's laptops exposed to.
- **DSA** is gone. OpenSSH removed it years ago. If you still have `id_dsa` on a machine, that machine has bigger problems.

The date suffix in the comment is the only "process" I ask for on my teams. It costs nothing and makes the `ssh-add -l` I described above actually readable.

## The `~/.ssh/config` pattern that scales

Most engineers I work with use maybe 10% of what `~/.ssh/config` can do. The four features you actually need:

```ssh-config
# ~/.ssh/config

# A named bastion in one place
Host bastion-prod
    HostName bastion-prod.corp.example.com
    User hagzag
    IdentityFile ~/.ssh/id_ed25519_prod
    IdentitiesOnly yes

# Everything inside goes THROUGH the bastion with one line
Host *.internal.prod
    ProxyJump bastion-prod
    User hagzag
    IdentityFile ~/.ssh/id_ed25519_prod
    IdentitiesOnly yes

# Conditional per-project identity
Match host *.lab.example.com exec "test -f ~/.ssh/id_ed25519_lab"
    IdentityFile ~/.ssh/id_ed25519_lab
    IdentitiesOnly yes
```

`ProxyJump` (the `-J` flag on the command line) is the single most underused SSH feature in the industry. It replaces `ssh -A` with agent-forwarding-to-bastion-then-ssh-again dances — which, when misconfigured, leak your laptop's entire agent to the bastion root account. ProxyJump keeps the cryptographic handshake end-to-end from your laptop to the target, using the bastion purely as a TCP relay. That's the architecture you want.

[IMAGE_PROMPT: Two side-by-side network diagrams. Left ("agent forwarding — don't"): laptop → bastion with "SSH_AUTH_SOCK" exposed → target; a shadowy figure labeled "root@bastion" is grabbing the agent socket. Right ("ProxyJump — do"): laptop → bastion (TCP relay only, no agent) → target, with the encrypted channel drawn as an unbroken line from laptop to target through the bastion.]

## Bastions buy you something — and add something

The honest balance sheet on jump hosts:

**What you gain.** A choke point where you can centralize logging (`auditd`, session recording via `tlog` or Teleport), a single ingress to harden (no direct SSH to the fleet), and a seam at which to apply MFA (PAM + FIDO2 or a proxying service).

**What you add.** An always-on, internet-facing SSH service that must be patched, a shared-tenancy machine with all the privilege-escalation opportunities that implies, and a target that attackers specifically hunt because compromising it is a force multiplier. The bastion that isn't continuously monitored is a worse security posture than no bastion at all.

This is the exact tension that showed up, in its fullest form, at a **global telco software vendor with thousands of bastion-fronted hosts** where I spent a long engagement. Tens of thousands of Linux boxes, dozens of environments, a handful of regional bastions carrying every interactive session. The `authorized_keys` files on those bastions were the single most sensitive piece of configuration in the entire estate — and nobody could tell you, with a straight face, how often they were pruned. Static keys at that scale aren't a SSH hygiene problem. They're an identity-management crisis in a trench coat.

## Certificates: the escape hatch that's been there for 15 years

OpenSSH has supported **user and host certificates** since 2010 (OpenSSH 5.4). A certificate is a short-lived, CA-signed artifact binding a public key to an identity (`-I "hagzag@laptop"`), a validity window (`-V +1h`), and — optionally — a principals list that restricts which accounts it can log in as. Both sides verify the CA signature instead of consulting a file.

On the server side, you replace the `authorized_keys` smokestack with one line:

```sshd_config
# sshd_config on every host in the fleet
TrustedUserCAKeys /etc/ssh/ca-user.pub
HostCertificate    /etc/ssh/ssh_host_ed25519_key-cert.pub
AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
```

On the client side, you get a fresh cert every morning (or every request) from something that knows who you are — Teleport, Smallstep `step-ca`, Hashicorp Vault's SSH engine, or a raw OpenSSH CA behind your SSO. The cert expires in an hour. If your laptop is stolen, the window of exposure is a lunch break, not an incident-response retrospective.

The transition is the hard part, not the steady state. At the telco vendor above, moving from static keys to signed certificates across the bastion estate took the better part of a year — but the audit posture on the other side was unrecognizable. The key-sprawl slide in every quarterly security review went from a growing bar chart to a flat line at zero.

## DNS, briefly — the SSHFP hook

Every time you SSH to a new host and see *"The authenticity of host 'x' can't be established — continue?"*, you're doing manual trust-on-first-use. **SSHFP records** (RFC 4255) publish the server's host key fingerprint in DNS, so a client with `VerifyHostKeyDNS yes` can answer that prompt automatically.

The catch — and this is the first hint of where DNS goes in later posts — SSHFP is only as trustworthy as the zone that serves it. Without **DNSSEC**, you've just traded TOFU for "trust whatever my resolver hands me." Most enterprises solve this the other way: bake `known_hosts` via configuration management, or use signed host certificates and let the CA handle it. But SSHFP + DNSSEC is the clean architectural answer, and it previews the bigger pattern — *DNS as a trust-delivery mechanism* — that we'll come back to in Parts 5 and 6.

## Hands-on: an SSH CA in k3d

The full walkthrough (CA keypair, host cert signing, bastion + two internal pods, ProxyJump across them, and an `ssh-audit` run that passes the hardened bastion and fails a deliberately-weakened one) lives in the companion repo: [`github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part2`](https://github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part2).

The short version of what you'll do:

```bash
# From practice/part2/
./run.sh                        # creates cluster, CA, host certs, user cert (1h)
ssh -F ./ssh_config internal-a  # ProxyJumps via bastion, cert auth end-to-end

# Then harden, or break, sshd:
ssh-audit -p 2222 127.0.0.1     # against the NodePort-exposed bastion
```

The aha moment: `ssh-add -l` shows nothing static. `ssh-keygen -L -f ~/.ssh/id_ed25519-cert.pub` shows a valid-until stamp an hour from now. Rotate the CA once and the whole fleet rotates with it.

## Where this leaves you

SSH did the job we needed in 1995, and for interactive host administration it is still the baseline in 2026. But the job description has quietly expanded. "SSH into a machine" was the use case SSH was designed for. "Give my laptop access to the corporate network, wherever I'm sitting" was not. That second use case demanded a different shape of solution — a tunnel at the network layer rather than a crypto upgrade at the application layer — and in Part 3 we meet the first wave of it: OpenVPN, IPsec, and the TLS-tunnel family.

Keep your ed25519 keys. Start signing certificates. And read the next post when it lands.

---

## Social Snippets

### LinkedIn
"SSH is solved" is the most dangerous sentence in your runbook. It works on 10 hosts, scales to shadow IAM by 10,000, and turns your bastions into the crown jewels.

Part 2 of my seven-part series on the evolution of remote access is live. We cover why ed25519 is the default in 2026, how `ProxyJump` replaces the agent-forwarding dance, why signed certificates are the escape hatch OpenSSH has shipped for 15 years, and the pragmatic cost of running bastions at telco scale. Every post ships a runnable k3d lab — Part 2 stands up an OpenSSH CA, a bastion, and two internal pods, so you can watch an hour-long cert auth in action.

#DevOps #SSH #ZeroTrust #PlatformEngineering #Security

### X (Twitter)
"SSH is solved" is the most dangerous sentence in your runbook.

Part 2 of the Zero Trust evolution series: ProxyJump, ed25519, and why static keys at fleet scale are an identity crisis in a trench coat.

#DevOps #SSH #ZeroTrust

### Facebook
Part 2 of "From Trusted Wires to Zero Trust" is up. The cryptographic turn that replaced telnet — and why it's *still* the baseline 30 years in. Includes a k3d lab that stands up an OpenSSH certificate authority in about three minutes.

### Instagram
Static keys → shadow IAM. Signed certificates → rotation. The SSH post you didn't know you needed. Part 2 of 7 is live. 🔐⏱️

#DevOps #SSH #ZeroTrust #PlatformEngineering #Kubernetes

---

## Further Reading

- [OpenSSH Certificate Format](https://man.openbsd.org/ssh-keygen#CERTIFICATES) — the canonical reference
- [Teleport's "A Comprehensive Guide to SSH Authentication"](https://goteleport.com/blog/how-to-ssh-properly/)
- [Smallstep's `step-ca` SSH docs](https://smallstep.com/docs/step-ca/provisioners/)
- [RFC 4255 — DNS SSHFP records](https://datatracker.ietf.org/doc/html/rfc4255)
- [`ssh-audit`](https://github.com/jtesta/ssh-audit) — the tool in the k3d lab

---

*Originally published on [Medium](MEDIUM_URL_PLACEHOLDER) on 2026-04-20.*
*Cross-posted to [portfolio.hagzag.com](https://portfolio.hagzag.com/blog/ssh-and-the-cryptographic-turn/).*
*Previous in series: [Part 1 — From Trusted Wires to the Open Internet](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28).*
