---
title: "From Trusted Wires to the Open Internet"
meta_title: "From Trusted Wires to the Open Internet — Remote Access, Part 1"
description: "Why telnet, rsh, and finger made sense once — and why every modern remote-access control traces back to the moment the wire stopped being trusted."
date: 2026-04-20T09:00:00+00:00
image: "/images/blog/2026/from-trusted-wires-to-the-open-internet/cover.png"
categories:
  - "DevOps"
  - "Security"
tags:
  - "remote-access"
  - "networking"
  - "zero-trust"
  - "history"
  - "osi-model"
  - "dns"
  - "kubernetes"
  - "k3d"
draft: false
author: "Haggai Philip Zagury"
medium_url: "https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28"
---

## TL;DR

Before the internet was *the* internet, it was "our network." Cleartext protocols like telnet, rsh, rlogin, and finger weren't carelessness — they were a rational answer to a world where the wire itself was the trust boundary. The moment that boundary stopped being physical, every remote-access technology we've built since has been an attempt to replace it with something else. This post, the first in a seven-part series, goes back to the beginning so the evolution that follows actually makes sense.

> *This is a written, expanded version of material I've taught for years in my private KubeExperience workshops and referenced in talks. If you've heard me tell this story before, this is the permanent reference — written once so I can point you here.*

## Hooking the modem in

The first time I badged into a real two-story server room, I remember the click of the cardkey reader more than I remember any of the actual servers. The room belonged to a security-industry employer with a self-managed on-prem datacenter — row after row of racks, two floors of cabling, HVAC you could hear from the elevator. Getting in required three things: your card, a PIN, and someone willing to vouch for you if the card reader had a bad day. Once you were inside, the network was the network. There was no "logging in" to a switch from the kitchen. There was a KVM trolley and a spool of Cat-5.

That's the world cleartext protocols were designed for. Not a mistake, not laziness, not "they didn't know any better" — a perfectly reasonable engineering response to a physical world where **trust equals cardkey access**.

[IMAGE_PROMPT: Split illustration — left side shows a closed campus/datacenter with a moat, drawbridge, and a single cardkey reader as the sole trust boundary; right side shows the same building with the moat drained and every wire exiting into a chaotic mesh labeled "the open internet". Evocative, slightly isometric.]

## The OSI ladder (we'll use this all series)

Every part of this series places the technology it discusses on the OSI model, because "which layer is the trust boundary living on?" is the single most useful question in remote access.

The quick refresher, top-down:

- **L7 — Application** (HTTP, SSH, telnet, DNS queries)
- **L6 — Presentation** (TLS, mostly — where encryption and serialization meet)
- **L5 — Session** (RPC-style session state; mostly an academic layer in 2026)
- **L4 — Transport** (TCP, UDP — ports and reliability)
- **L3 — Network** (IP, IPsec, routing)
- **L2 — Data Link** (Ethernet, ARP, MAC addresses)
- **L1 — Physical** (the actual copper, fibre, radio)

In the trusted-wire world, the security boundary lives at **L1–L3**. The cardkey controls who can plug into the switch; the switch controls which VLAN they land on; the router controls which subnets they reach. If you're physically on the wire and routed to the subnet, you're trusted. Period. Everything above L3 — your login, your password, your command — runs in the clear, because the layers that could see it belong to your employer.

[IMAGE_PROMPT: A clean, technical OSI model diagram, 7 layers stacked. A translucent red "trust boundary" band spans L1–L3 with the label "physical era". A dotted line marks where subsequent posts will place their boundaries (L7 for SSH, L3 for IPsec, etc.) — a teaser for the rest of the series.]

## Why telnet, rsh, and friends weren't crazy

Take `telnetd`. It opens a TCP socket on port 23 and faithfully pipes whatever you type to a login shell on the other end. No TLS. No session key. Your password travels as ASCII bytes.

In a 1988 university CS department, that's fine. The wire between your VT100 and the VAX is a physical cable in the same building, on a network that does not peer with anyone who isn't also on the physical premises. Anyone who could sniff that traffic had already defeated the cardkey, the building guard, and whatever custodian rules were in place for the basement. If your adversary has that level of access, adding TLS to telnet is not your top priority.

The same logic explains `rsh` and `rlogin` (which cheerfully honored a `.rhosts` file full of hostnames, because *the sender's IP was the identity*), `finger` (which would happily tell any caller who was logged in to your machine and when they last read mail), and `rsync` running over `rsh` for years after SSH shipped. These weren't security flaws in their original deployment context. They became security flaws when the context changed.

## `hosts.txt`, DNS, and the first federated trust system

There's a parallel story on the naming side that I want to plant here because it recurs in every later post.

Before DNS existed, name-to-address resolution on the ARPANET was a single flat file: `HOSTS.TXT`, maintained by the Network Information Center at SRI and periodically copied — via FTP, of course — to every participating host. It worked fine when "every host" was a few hundred machines. By the early 1980s it was already breaking: the file kept growing, the single authority was a bottleneck, and propagating changes was a multi-day affair.

RFC 882 and 883 (1983) introduced DNS: a distributed, hierarchical, delegated naming system where different zones could be authoritative for different slices of the namespace. That architectural pattern — *replace a single centralized trust artifact with a federated one that delegates authority* — is the same pattern that shows up again when we move from static SSH keys to signed certificates (Part 2), from corporate CAs to WebPKI, from LDAP to OIDC (Part 5), and ultimately from "a VPN lets you in" to "every request is an identity-authenticated policy decision" (Part 6).

DNS was, in other words, the first real distributed trust system to run on the internet. And it quietly becomes more important in every subsequent post in this series, until by Part 6 it's functioning as a policy-enforcement plane. Keep an eye on it.

## The wire stops being trusted

Two shifts broke the physical-boundary model, roughly in parallel.

The first was the commercial internet. When the NSFNET backbone transitioned to commercial traffic in 1995 and ISPs started peering, "our network" and "someone else's network" lost the clean air-gap they'd had on university backbones. Your telnet session from a home dial-up in 1996 was traversing links operated by strangers. The threat model flipped without anyone filing a ticket.

The second was the arrival of adversaries who understood this. The 1988 Morris worm was the first mass-scale demonstration that the wire was a two-way street; by the late 1990s, packet sniffers were a freely-available part of any junior sysadmin's toolkit, and capturing plaintext telnet credentials off a lab subnet was a lunch-break exercise. If you were paying attention, it was no longer safe to assume your L1 was trusted. If you weren't, you found out the hard way.

[IMAGE_PROMPT: A horizontal timeline spanning 1969 ARPANET → 1983 DNS (RFC 882/883) → 1988 Morris worm → 1995 NSFNET commercialization → 1995 SSH-1 → 1998 SSH-2. Each event has a one-line caption explaining its significance to the trust story.]

## Why this still matters

You might think this is all archaeology. It isn't. Every legacy protocol you still see in production is a relic of this era, and the reason it's *still there* is almost always that someone, somewhere, is implicitly relying on a trusted-wire assumption that no longer holds.

A short list of things I've found still running at clients in the last five years: `rsh` between batch nodes on a "private" subnet (which was private until a helpful network team peered it with the rest of the WAN). `finger` on an internal jump host that a contractor had helpfully exposed via a misconfigured LB rule. `telnet`-based consoles on network appliances managed from a shared jumpbox. Every one of those was a perfectly reasonable choice in its original context, and every one of them became a finding the moment the context changed.

This is also the frame to hold onto for the rest of the series: **every remote-access technology we'll discuss exists to replace the trusted wire with something else** — first cryptography on top of an untrusted network (Part 2), then an entire encrypted network overlay (Parts 3 and 4), then identity as the new boundary (Part 5), and finally identity plus continuous verification as a first-class enforcement plane (Part 6). The wire itself doesn't come back. We just get better at living without it.

## Hands-on: feel the cleartext

Reading about cleartext protocols and *seeing your own password on a pcap* are different experiences. Here's the smallest possible lab to make the point visceral — runs locally on a k3d cluster in a couple of minutes.

**Companion repo**: the full lab (manifests, `run.sh`, cleanup) lives at [`github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part1`](https://github.com/hagzag/the-road-2-zerotrust/tree/main/practice/part1). The snippet below is the shortest path; the repo README has the full walkthrough plus takeaway questions.

```bash
# 1. Spin up a local cluster
k3d cluster create trusted-wire --agents 1

# 2. Deploy a telnetd pod + a tcpdump sidecar on the same pod network
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: telnet-demo }
spec:
  shareProcessNamespace: true
  containers:
    - name: telnetd
      image: ghcr.io/inetutils/telnetd:latest   # pin to a real tag in practice
      ports: [{ containerPort: 23 }]
    - name: sniffer
      image: nicolaka/netshoot
      command: ["tcpdump","-A","-i","any","port","23","-w","/tmp/telnet.pcap"]
      volumeMounts: [{ name: cap, mountPath: /tmp }]
  volumes: [{ name: cap, emptyDir: {} }]
EOF

# 3. In another terminal, telnet in and log in as any user the image accepts
kubectl exec -it telnet-demo -c telnetd -- \
  sh -c "apk add --no-cache busybox-extras && telnet 127.0.0.1 23"

# 4. Pull the pcap and open it in Wireshark
kubectl cp telnet-demo:/tmp/telnet.pcap ./telnet.pcap -c sniffer
wireshark ./telnet.pcap    # Follow TCP Stream → read the password in ASCII
```

Two observations readers almost always make at step 4, in this order: *"oh — that's literally my password"*, and *"wait, how is this ever safe?"*. The answer to the second question is the punchline of this post: it was safe when the wire was trusted, and it hasn't been safe since.

A one-shot runner (`run.sh`) ships in the repo alongside the labs for the rest of the series. Each subsequent post will link to its own `practice/partN/` folder in [the-road-2-zerotrust](https://github.com/hagzag/the-road-2-zerotrust) so you can walk the stack linearly.

## What broke, and where we go next

By the mid-1990s, the physical trust boundary had evaporated for any serious operator. The gap needed filling — fast, practically, and ideally without a forklift upgrade of every application that spoke telnet or rsh. The answer was a single protocol that bolted a real cryptographic session onto the existing TCP-based shell model and called it a day.

That protocol, of course, was SSH. In Part 2, we'll look at how it replaced telnet/rsh almost overnight, why it's still the baseline three decades later, and why "SSH is solved" is the most dangerous sentence in your runbook.

---

## Social Snippets

### LinkedIn
Before the internet was *the* internet, it was "our network." Cleartext protocols like telnet and rsh weren't careless — they were a rational response to a world where the cardkey was the security boundary. That world is gone, but the relics are still in production.

Part 1 of a seven-part series on the evolution of remote access — from trusted wires to Zero Trust. Each post ships a local k3d lab you can run in minutes. This one walks through why cleartext ever made sense, what broke, and previews how DNS quietly becomes a first-class security plane by the end of the series.

#DevOps #ZeroTrust #Networking #Security #PlatformEngineering

### X (Twitter)
Before the internet was *the* internet, it was "our network." telnet and rsh weren't careless — they were the right answer to a trusted-wire world. Part 1 of a 7-part series on the evolution of remote access is up.

#DevOps #ZeroTrust #Networking

### Facebook
New blog series: "From Trusted Wires to Zero Trust." Part 1 is out — a short history of why we ever sent passwords in the clear, and why every remote-access control since traces back to the moment the wire stopped being trusted. Includes a tiny k3d lab you can run in five minutes to watch your own telnet password fly past in Wireshark.

### Instagram
From trusted wires to Zero Trust — Part 1 of 7. Why cleartext protocols weren't careless, and what broke. Lab included. 🔐🪢

#DevOps #ZeroTrust #Networking #PlatformEngineering #Kubernetes

---

## Further Reading

- RFC 882 / 883 — the original DNS specifications (Mockapetris, 1983)
- "An Evening with Berferd" — Bill Cheswick's 1992 paper on early intrusion detection; a snapshot of the trusted-wire mindset starting to crack
- "Reflections on Trusting Trust" — Ken Thompson, 1984 — adjacent but essential background
- The SSH-1 original announcement (Tatu Ylönen, 1995) — we'll open Part 2 with it

---

*Originally published on [Medium](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28) on 2026-04-20.*
*Cross-posted to [portfolio.hagzag.com](https://portfolio.hagzag.com/blog/from-trusted-wires-to-the-open-internet/).*
