---
title: "WireGuard: Why Simpler Won"
meta_title: "WireGuard — Why Simpler Won — Remote Access, Part 4"
description: "WireGuard won because it's boring — a short config, a fixed crypto suite, and a kernel module the size of a caffeine habit. Here's the practitioner's case for it in 2026."
date: 2026-04-20T12:00:00+00:00
image: "/images/blog/2026/wireguard-why-simpler-won/cover.png"
categories:
  - "DevOps"
  - "Security"
tags:
  - "wireguard"
  - "vpn"
  - "remote-access"
  - "zero-trust"
  - "tailscale"
  - "dns"
  - "kubernetes"
  - "k3d"
draft: false
author: "Haggai Philip Zagury"
medium_url: ""
---

## TL;DR

WireGuard did not win by out-securing OpenVPN and IPsec on a whiteboard. It won by being **boring**: a fixed cipher suite, a kernel module small enough to audit in an afternoon, a UDP-only handshake, and a config file short enough to paste into a chat. Simplicity is the only sustainable security property, because everything else degrades under operational pressure. WireGuard also keeps the "inside the tunnel is trusted" flaw, which is why Part 5 moves the trust boundary one level higher — onto identity. This is Part 4 of a seven-part series; [Part 3](https://portfolio.hagzag.com/blog/vpns-openvpn-ipsec-and-the-tls-tunnel/) covered the OpenVPN/IPsec era that WireGuard displaced.

> *This is a revised, written version of the "why WireGuard actually won" walk-through I've done in private KubeExperience workshops and more than a few whiteboard sessions with platform teams. If you've heard me argue that simplicity is a security property, this is where that argument lives in print.*

## 4,000 lines vs 400

The most persuasive demo I ever gave on WireGuard was not a performance chart. It was a single `wc -l` on the project source tree next to the same command run against the OpenVPN and strongSwan trees. Roughly four thousand lines of code vs several hundred thousand, depending on what you count. You can read the entire WireGuard kernel module in a long evening. You cannot read OpenVPN + OpenSSL + the kernel's TUN driver in a lifetime.

That gap is the whole story. Most of what follows is a consequence of it.

[IMAGE_PROMPT: A side-by-side comparison graphic. Left panel: a big blocky diagram labeled "OpenVPN + OpenSSL + IPsec/strongSwan" with many internal components (TLS state machines, cipher negotiation, NAT-T, rekeying, compat shims) drawn as a tangled web. Right panel: a single small clean box labeled "WireGuard — ~4k LoC, fixed ciphers, UDP only", with 5 boxes arranged in a straight line: Noise → Curve25519 → ChaCha20-Poly1305 → BLAKE2s → UDP.]

## What WireGuard actually is

Stripped down: WireGuard is a **routed L3 overlay**. It opens a single UDP port, runs a Noise-pattern handshake to establish keys with each peer, and then encapsulates IP packets as encrypted UDP datagrams. The crypto is fixed — **Curve25519** for key agreement, **ChaCha20-Poly1305** for the AEAD, **BLAKE2s** for hashing — and there is no negotiation at runtime. If the day comes that any of those primitives falls, WireGuard ships a new major version. That is the upgrade path. There is no cipher-suite matrix.

A two-peer config is the whole mental model:

```ini
# /etc/wireguard/wg0.conf — peer A
[Interface]
PrivateKey = <peer-A-privkey>
Address    = 10.99.0.1/24
ListenPort = 51820

[Peer]
PublicKey  = <peer-B-pubkey>
AllowedIPs = 10.99.0.2/32
Endpoint   = peer-b.example.com:51820
PersistentKeepalive = 25
```

`AllowedIPs` is the one line that confuses everyone the first time. It's both the cryptographic routing table ("packets to 10.99.0.2 must come from this peer") and the forwarding table ("packets to 10.99.0.2 get encrypted to this peer's key"). One field, both jobs. That tight coupling is why the config is short — and why spoofing an inner IP through a WireGuard tunnel is not a thing.

## Kernel, UDP-only, and what you give up

Three opinionated design choices are worth naming:

**Kernel-native** (mainlined in Linux 5.6). Packets ride the TUN device inside the kernel — no user-space process in the hot path. That is where WireGuard's "fast" reputation comes from: less context switching, not faster crypto.

**UDP only.** No TCP fallback. If your network drops UDP — some hotels, some corporate egress, some nation-states — WireGuard just doesn't work. OpenVPN's TCP-over-TLS fallback was pragmatic cover. WireGuard's answer is "wrap it in `udp2raw`," which is operationally annoying.

**No crypto agility.** You cannot negotiate a different AEAD. Some view this as a bug; I view it as *the* feature. Crypto agility is what gave us Heartbleed, POODLE, and every IKE downgrade attack of the last 15 years. When a primitive weakens, the remediation is a package update, not a configuration audit.

## Mesh overlays — the Tailscale pattern

The other reason WireGuard won: its simplicity created space for a layer above it. Nobody deploys raw WireGuard for a fleet of 500 laptops. They deploy **Tailscale**, **Headscale**, **Netmaker**, or **Netbird** — coordination planes that handle peer discovery, key rotation, NAT traversal, and identity-aware access policy, with WireGuard as the encrypted substrate. Raw WireGuard is fine for two servers or a homelab; once you have a fleet, the control plane is the interesting product surface and the data plane is "whatever WireGuard does." Part 6 will circle back — Cloudflare WARP, Tailscale, and Twingate all lean on it.

## Performance, briefly

`iperf3` across an otherwise-idle tunnel consistently puts WireGuard in the same ballpark as native IPsec and noticeably ahead of OpenVPN on the same hardware. In the k3d lab below, on a modern laptop:

```
# iperf3 control (no tunnel)      39.9 Gbits/sec
# iperf3 over WireGuard           2.99 Gbits/sec
# iperf3 over OpenVPN (UDP)        810 Mbits/sec
```

Absolute numbers are not the point (your laptop is not a datacenter). The **ratio** is — ~3x on this hardware, wider on a real NIC with AES-NI. Across a thousand laptops, that's the difference between "my VPN is fine" and "why is my VPN breaking Zoom."

## DNS, again — MagicDNS and the naming plane

Every WireGuard deployment of any size reaches the same realization: once you have a mesh of peers, you need names, not IPs. Tailscale's **MagicDNS** is the canonical example — every node gets a stable name (`laptop.hagzag.ts.net`) that resolves only inside the mesh. The overlay *is* the naming plane.

This is the first time in this series that DNS and the transport are **co-designed**. In Part 3, DNS was pushed through the tunnel and you hoped clients honoured it. In a Tailscale-style mesh, DNS inside the mesh is served by the control plane — a stolen laptop that falls out of the mesh also falls out of the namespace. Revocation and naming are the same operation. Split-DNS in a mesh is still harder than it looks in the slide deck, and every Tailscale user has a coffee-shop story to prove it.

[IMAGE_PROMPT: Mesh vs. hub-and-spoke comparison. Left: hub-and-spoke VPN, 8 clients all routing through a single VPN concentrator in the middle, with arrows showing that traffic between clients has to go through the hub. Right: a WireGuard/Tailscale mesh, 8 clients with a control-plane icon floating above (not in the data path), direct encrypted links between every pair of peers. Caption: "Control plane coordinates; data plane is direct."]

## The blocking story, again

WireGuard is also DPI-detectable. The handshake has a deterministic shape — first message is 148 bytes, second is 92, both with fixed header bytes — and state-level filters classify it cleanly. The Part 3 legal/ethical caveat applies here unchanged: an obfuscation ecosystem exists (including some WireGuard-specific shims), and this post is **not** a circumvention guide. The point for the platform engineer is more prosaic — if you operate a WireGuard mesh that crosses national egress boundaries, assume it will occasionally be blocked outright, and plan accordingly.

## An anchor from the field

The WireGuard-as-substrate pattern showed up cleanly in one engagement with **a converged-cloud enterprise bridging local datacenters to three hyperscalers**. Before: a forest of IPsec site-to-site tunnels, each with its own MTU headaches, NAT-T quirks, and operator-on-call rotation. After: a WireGuard mesh with a control plane that abstracted the peering. MTU stopped being an oncall topic. Tunnel flaps became a self-healing event rather than a page. The crypto didn't get meaningfully better; the **blast radius of any single tunnel failure** did, and that was the actual prize.

## Hands-on: two peers, one capture, an iperf3 run

The full lab — a two-peer WireGuard mesh on a k3d cluster, a `tcpdump` capture of the UDP/51820 handshake, a WireGuard-aware classifier, and an `iperf3` run so you can see the perf numbers on your own hardware — lives at [`github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part4`](https://github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part4).

Short version:

```bash
# From practice/part4/
./run.sh                          # create cluster, deploy peer-a and peer-b
kubectl exec -n wg-lab deploy/peer-a -- ping -c3 10.99.0.2
./bench.sh                        # iperf3 through the tunnel + a control run
./capture.sh                      # 20s tcpdump on UDP/51820 → wg.pcap
```

The aha moment is not a dramatic screenshot — it's that the whole thing is boring. Config is 8 lines per peer. Peers come up in milliseconds. `wg show` tells you the last handshake happened four seconds ago. That's the entire user experience, and that's the point.

## Where this leaves you

WireGuard is the best answer the VPN lineage produced. If you're running OpenVPN for remote access in 2026, a migration plan is a reasonable Q3 project. If you're running IPsec between datacenters, keep running it — but know that a WireGuard mesh with a coordination plane is a credible modernization target now, not in three years.

It still keeps the flaw we started naming in Part 3: *inside the tunnel, you are trusted*. A stolen laptop inside a WireGuard mesh can walk to every service that mesh reaches. The transport got better. The trust model didn't.

Fixing the trust model is what the rest of the series is about. In Part 5 we move the boundary off the network entirely and onto **identity** — AuthN, AuthZ, MFA, and why "we require MFA" is nowhere near enough.

---

## Further Reading

- [WireGuard whitepaper (Donenfeld, 2017)](https://www.wireguard.com/papers/wireguard.pdf) — still the cleanest explanation
- [The Linux 5.6 merge commit](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=e7096c131e5161fa3b8e52a650d7719d2857adfd) — the moment WireGuard became boring
- [Tailscale: How NAT traversal works](https://tailscale.com/blog/how-nat-traversal-works/) — the single best explainer of what a coordination plane actually does
- [Headscale](https://github.com/juanfont/headscale) — open-source Tailscale control plane
- [`wg(8)` man page](https://man7.org/linux/man-pages/man8/wg.8.html) — the entire user-facing interface in one page

---

*Originally published on [Medium](MEDIUM_URL_PLACEHOLDER) on 2026-04-20.*
*Cross-posted to [portfolio.hagzag.com](https://portfolio.hagzag.com/blog/wireguard-why-simpler-won/).*
*Previous: [Part 3 — VPNs: OpenVPN, IPsec, and the TLS Tunnel](https://portfolio.hagzag.com/blog/vpns-openvpn-ipsec-and-the-tls-tunnel/).*
*First in series: [Part 1 — From Trusted Wires to the Open Internet](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28).*
