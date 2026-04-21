---
title: "VPNs: OpenVPN, IPsec, and the TLS Tunnel"
meta_title: "VPNs — OpenVPN, IPsec, and the TLS Tunnel — Remote Access, Part 3"
description: "VPNs extended the trust boundary over the public internet — and preserved the flaw at the heart of it. A practitioner's tour of OpenVPN, IPsec, split-DNS, and the DPI blocking era."
date: 2026-04-20T11:00:00+00:00
image: "/images/blog/2026/vpns-openvpn-ipsec-and-the-tls-tunnel/cover.png"
categories:
  - "DevOps"
  - "Security"
tags:
  - "vpn"
  - "openvpn"
  - "ipsec"
  - "remote-access"
  - "zero-trust"
  - "dns"
  - "kubernetes"
  - "k3d"
draft: false
author: "Haggai Philip Zagury"
medium_url: ""
---

## TL;DR

VPNs solved a real problem: *give a laptop on a hotel Wi-Fi the same network reachability it would have from inside the office.* They did it by tunnelling packets across the public internet under an umbrella of cryptography — and in the process, they preserved the exact flaw we spend the rest of this series unlearning: **once you're inside the tunnel, you're trusted.** OpenVPN lives at L4+, IPsec at L3, and both carry the same conceptual weight. This is Part 3 of a seven-part series; Parts [1](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28) and 2 set up the physical-to-host trust migration, and Part 4 (WireGuard) is why simpler finally won.

> *This post distills material I've walked through inside my private KubeExperience workshops and in consulting engagements for the better part of a decade. If you've heard me argue "VPNs are a drawbridge, not a firewall," this is the written version of that argument.*

## The late-night call from a hosting provider

I once spent most of a weekend on a call with a hosting provider with connections to three international backbone carriers, one per datacenter. Between those sites ran a small mesh of site-to-site IPsec tunnels carrying replication traffic, management plane, and inter-region internal DNS. One tunnel flapped — the one carrying the internal resolvers the other two sites pointed at — and customers across three countries watched sites go dark because the app tiers couldn't find their own databases.

Nothing crypto-interesting happened that night. The cryptography was fine. The architecture — a single tunnel failure cascading into a cross-region outage because DNS was inside the tunnel — was the lesson. VPNs are *topology*. And topology has failure modes that no amount of cipher-suite tuning will save you from.

[IMAGE_PROMPT: Two architectural diagrams side by side, labeled "Site-to-Site VPN" and "Remote-Access VPN". Left: three datacenter icons connected by a triangle of IPsec tunnels, each tunnel drawn as a thick fibre-optic-style pipe with a small padlock. Right: a laptop on a hotel-Wi-Fi icon with a single OpenVPN tunnel running across the open internet to a "corp network" cloud, drawbridge-style.]

## Two problems, one toolbox

The single biggest confusion in VPN land is that **site-to-site** and **remote-access** look the same on the packet capture but solve fundamentally different problems.

- **Site-to-site** connects two (or more) networks that should act as one — offices, datacenters, clouds. The "users" are routers. Tunnels are long-lived, MTUs are tuned, routing is symmetric, and a failure is a multi-team incident.
- **Remote-access** connects a single laptop (or phone, or IoT device) to a corporate network. The user is a person. Tunnels are short, transient, and constantly reconnecting across NAT boundaries that no network engineer vetted.

Both are "VPNs." Neither is the other. Most of the pain I've seen in VPN operations comes from teams applying a mental model from one to the other — running remote-access-style client software between datacenters, or treating every user tunnel as if it were a fibre-backed pipe.

## OpenVPN: a TLS tunnel in user space

OpenVPN is the easiest to reason about. Two processes — one client, one server — open a TLS session over either **UDP or TCP**, then encapsulate IP packets as the TLS payload. Your `ping`, your HTTP, your noisy npm install, all get wrapped in TLS records and shipped over the internet.

This is pragmatic in three directions at once. It runs in user space, so you don't need a kernel module. It uses TLS, so it reuses the entire PKI and cipher ecosystem you already know. It runs over TCP when UDP is blocked, so it gets through almost any firewall that doesn't actively fingerprint it. A minimal, annotated server config:

```conf
# /etc/openvpn/server.conf — minimal, annotated
port 1194
proto udp                       # udp preferred; tcp for hostile networks
dev tun                         # routed tunnel, not bridged

ca   /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/server.crt
key  /etc/openvpn/pki/server.key
dh   /etc/openvpn/pki/dh.pem
tls-crypt /etc/openvpn/pki/tls-crypt.key   # HMAC-wrapped control channel

server 10.8.0.0 255.255.255.0   # client address pool

# The bit that matters for DNS (see below):
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 10.8.0.1"
push "dhcp-option DOMAIN corp.internal"

cipher AES-256-GCM
auth   SHA256
keepalive 10 60
user   nobody
group  nogroup
persist-key
persist-tun
status /var/log/openvpn/status.log
```

Three decades of field-tested pragmatism and about five minutes to stand up. That's a lot of the reason OpenVPN became the default for a generation of remote-access deployments.

## IPsec: the enterprise default

IPsec is older, harder to read, and still the right answer for site-to-site. It lives at **L3** rather than L4, which means it tunnels IP packets *between* IP stacks rather than over a user-space process. IKEv2 (RFC 7296) negotiates the keys; ESP carries the encrypted payload; policy decides which flows get encrypted. A minimal strongSwan site-to-site config:

```conf
# /etc/ipsec.conf — strongSwan, two DC site-to-site
conn dc-east-to-west
    keyexchange=ikev2
    auto=route
    left=203.0.113.10        leftsubnet=10.10.0.0/16
    right=198.51.100.22      rightsubnet=10.20.0.0/16
    authby=secret            # PSK for brevity; cert-based in practice
    ike=aes256-sha256-curve25519!
    esp=aes256-sha256!
    keyingtries=%forever
    dpdaction=restart        # Dead Peer Detection — this is the clause that
                             # saves you during the 3am tunnel flap
```

At scale, IPsec's failure modes are different from OpenVPN's. MTU negotiation across IPv4-with-Path-MTU-Discovery-mostly-broken paths is a rite of passage. NAT traversal (NAT-T encapsulating ESP in UDP/4500) is ubiquitous and lightly understood. And the DPD clause above is, in my experience, the single line of config that does more operational good than any other in the file.

## The drawbridge mental model

Both OpenVPN and IPsec implement the same trust shape: **a hardened outer wall with a single gate, guarded by cryptographic authentication, and a soft interior**. Once you're in the tunnel, the network trusts you the way Part 1's campus network trusted a cable. Your VPN client's address lives inside the company's routable space. Your traffic hits internal DNS, internal apps, internal services — with nothing between you and them.

This is exactly the flaw **Zero Trust** (Parts 5 and 6) exists to fix. But it's worth naming the source of the flaw precisely: *VPNs moved the trust boundary from L1 to L3/L4, but they didn't remove the boundary.* There's still an inside and an outside. Anyone who reaches the inside is trusted to reach everything inside. "Lateral movement from a compromised VPN endpoint" is the modern spiritual successor to "packet sniffer on the lab subnet" from Part 1.

[IMAGE_PROMPT: A medieval castle cross-section. The moat and drawbridge are labeled "VPN tunnel + authentication." Inside the castle: a bunch of rooms (databases, Jenkins, file server, payroll, HR) with no doors between them — just open archways. A thief stands just inside the gate, smiling at the open archways. Caption: "The drawbridge protects the perimeter. It does not protect the interior."]

## Proxies, briefly

Forward proxies (Squid, corporate egress) log and enforce *outbound* policy; reverse proxies (Nginx, Envoy) front *inbound* traffic — they're not VPNs, but they're what Zero Trust builds on in Part 6; SOCKS proxies (including OpenSSH `-D` from Part 2) are per-application tunnels. All three coexist with VPNs and aren't substitutes for them.

## DNS: where the leaks live

Every VPN post eventually turns into a DNS post, and this is the point where it happens.

A **full-tunnel** VPN pushes all traffic — including DNS queries — through the tunnel. A **split-tunnel** VPN only tunnels traffic destined for the corporate subnets; everything else goes out over the local ISP. Each has legitimate uses, and each has a failure mode: full-tunnel balloons corporate egress and breaks country-specific services; split-tunnel leaks *internal* DNS queries to the local ISP if the split is naive.

A **DNS leak** is the technical term for "your 'private' VPN still sent `intranet.example.corp` to your ISP's resolver, which logged it." The fix is explicit: `push "dhcp-option DNS 10.8.0.1"` in OpenVPN and equivalent policy on the client. On Linux it's `systemd-resolved` per-link settings; on macOS it's `scutil --dns`; on Windows it's the long-suffering NRPT. This is the kind of misconfiguration that looks fine in functional testing and shows up in a pentest report a year later.

Keep this thread in mind: by Part 6, DNS becomes a **first-class policy enforcement plane** — not just a naming system. What we're papering over in Part 3 with `push "dhcp-option DNS"` becomes a centralized decision later.

## The state-actor angle (what exists, not how)

This is also the first remote-access technology that governments actively suppress. China's Great Firewall, Iran's and Russia's filtering regimes, and similar programs elsewhere use **Deep Packet Inspection** to fingerprint OpenVPN and IPsec handshakes on the wire. OpenVPN's opcode framing, IPsec's IKE cookies — both have characteristic byte patterns that a classifier can spot inside milliseconds.

An ecosystem of obfuscation technologies exists precisely because of this — `obfsproxy`, `stunnel`-wrapping of tunnels, `shadowsocks`, and others. I'm noting their existence because it's part of the landscape; this post is **not** a circumvention how-to. The legal and ethical calculus of bypassing a state block depends entirely on who you are, where you are, and why — and the people who need that guidance need it from a lawyer and a human-rights organization, not a DevOps blog. The k3d lab below fingerprints an OpenVPN handshake so you can *see* what a DPI classifier sees; what you do with that knowledge is your call.

## Hands-on: capture your own OpenVPN handshake

The full walkthrough — two pods on a k3d cluster (OpenVPN server + client), a `tcpdump` capture of the tunnel, and a Python **scapy** classifier that fingerprints the OpenVPN control-packet opcodes — lives in the companion repo: [`github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part3`](https://github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part3).

The short version:

```bash
# From practice/part3/
./run.sh                            # bring up OpenVPN server + client in k3d
./capture.sh                         # tcpdump the tunnel handshake
python3 classify.py ./openvpn.pcap   # prints opcode frequency + a verdict
```

The classifier prints something like:

```
Total UDP/1194 packets: 47
P_CONTROL_HARD_RESET_CLIENT_V2 : 1
P_CONTROL_HARD_RESET_SERVER_V2 : 1
P_CONTROL_V1                   : 12
P_ACK_V1                       : 9
P_DATA_V2                      : 24
Verdict: OpenVPN handshake (95% confidence)
```

That "95% confidence" is what DPI boxes do at line rate, for every connection, at the scale of a country's egress. It is not an academic exercise; it is the operational reality that drove WireGuard's design — and WireGuard's own DPI-detectability — in Part 4.

## Where this leaves you

VPNs work. They've worked for twenty-five years. At the right scale, with the right operational discipline, they still do. They are also complex, brittle across weird network paths, increasingly blocked, and architecturally wedded to a trust model the rest of this series dismantles.

The next technology in the stack was built on a radically different design principle — *be boring, and be kernel-native*. In Part 4 we look at **WireGuard**, why it won, and why "won" still comes with asterisks.

---

## Further Reading

- [RFC 7296 — IKEv2](https://datatracker.ietf.org/doc/html/rfc7296)
- [The OpenVPN protocol spec](https://build.openvpn.net/doxygen/network_protocol.html) — the opcode table used by the k3d lab's classifier
- [strongSwan IPsec documentation](https://docs.strongswan.org/) — the reference for site-to-site
- [GFWatch](https://gfwatch.org/) — public research on Great Firewall behavior (the landscape context for the DPI section)
- ["The Parrot Is Dead: Observing Unobservable Network Communications" (Houmansadr et al., 2013)](https://people.cs.umass.edu/~amir/papers/parrot.pdf) — foundational reading on protocol obfuscation

---

*Originally published on [Medium](MEDIUM_URL_PLACEHOLDER) on 2026-04-20.*
*Cross-posted to [portfolio.hagzag.com](https://portfolio.hagzag.com/blog/vpns-openvpn-ipsec-and-the-tls-tunnel/).*
*Previous: [Part 2 — SSH and the Cryptographic Turn](https://portfolio.hagzag.com/blog/ssh-and-the-cryptographic-turn/).*
*First in series: [Part 1 — From Trusted Wires to the Open Internet](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28).*
