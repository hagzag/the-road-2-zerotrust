# Part 3 — OpenVPN in k3d, plus a DPI Fingerprinter

**Companion lab for**: [VPNs: OpenVPN, IPsec, and the TLS Tunnel](https://portfolio.hagzag.com/blog/vpns-openvpn-ipsec-and-the-tls-tunnel/)
**Series**: [The Road to Zero Trust](../../README.md)
**Estimated time**: 5–10 minutes
**Prereqs**: Docker, [`k3d`](https://k3d.io), `kubectl`, Python 3.9+ with [`scapy`](https://scapy.net/), `tcpdump`

## What you'll see

Two Pods in one k3d cluster:

- `openvpn-server` — minimal OpenVPN server, UDP/1194, annotated config from the blog post
- `openvpn-client` — an OpenVPN client that dials the server and maintains the tunnel

You'll `tcpdump` the handshake, save it as `openvpn.pcap`, and then run `classify.py` — a small scapy script that walks the UDP/1194 packets, decodes the OpenVPN opcode byte, and prints a DPI-style verdict.

By the end you'll have felt three things:

1. How little it takes to stand up a "private" tunnel (this is why OpenVPN ran the world for 20 years).
2. How **visible** the handshake is on the wire even before you decrypt anything.
3. Why Part 4 (WireGuard) went out of its way to be **boring**.

## Legal/ethical note

This lab demonstrates the *detection* side of the censorship story — the same move a state-level DPI classifier makes. It does **not** include any circumvention tooling. Whether you run the lab, how you use the knowledge, and what you do with it in which jurisdiction is your call and your lawyer's. This repo doesn't help you bypass a state block.

## Run it

```bash
# from this directory
task run          # creates cluster, deploys server + client, tunnel comes up
task capture      # restarts client, captures handshake on server side → ./openvpn.pcap
task classify     # runs DPI classifier on the pcap
task test         # verifies all 5 assertions
task cleanup      # tears down the cluster
```

Expected classifier output (your numbers will vary):

```
Total UDP/1194 packets: 29
  P_CONTROL_HARD_RESET_CLIENT_V2 : 1
  P_CONTROL_HARD_RESET_SERVER_V2 : 1
  P_CONTROL_V1                   : 11
  P_ACK_V1                       : 8
  P_DATA_V2                      : 8
Verdict: OpenVPN handshake (95% confidence)
```

## What the classifier looks for

OpenVPN packets over UDP start with a single byte whose **top 5 bits are the opcode**. The opcode enum is stable and documented:

| Opcode value | Name |
|--------------|------|
| 1  | P_CONTROL_HARD_RESET_CLIENT_V1 |
| 2  | P_CONTROL_HARD_RESET_SERVER_V1 |
| 3  | P_CONTROL_SOFT_RESET_V1        |
| 4  | P_CONTROL_V1                   |
| 5  | P_ACK_V1                       |
| 6  | P_DATA_V1                      |
| 7  | P_CONTROL_HARD_RESET_CLIENT_V2 |
| 8  | P_CONTROL_HARD_RESET_SERVER_V2 |
| 9  | P_DATA_V2                      |

A classifier that sees a UDP flow with *some* opcodes in this range and the characteristic hard-reset kickoff pattern can decide "this is OpenVPN" in milliseconds, without touching the encrypted payload. That's it. That's the whole trick.

## File layout

```
practice/part3/
├── Taskfile.yaml            ← task run / capture / classify / test / cleanup
├── README.md
├── manifests/
│   ├── namespace.yaml
│   ├── openvpn-server.yaml  ← server + sniffer sidecar
│   └── openvpn-client.yaml  ← client (ConfigMap-injected ovpn) + sniffer sidecar
├── classify.py              ← scapy-based OpenVPN opcode classifier
├── run.sh                   ← bring cluster up, deploy, extract client.ovpn → ConfigMap, wait for tunnel
├── capture.sh               ← restart client + 30s tcpdump on server → ./openvpn.pcap
└── cleanup.sh
```

## How it works

1. `run.sh` creates the k3d cluster and deploys the OpenVPN server (with an init container that provisions PKI via easy-rsa).
2. After the server is ready, `run.sh` extracts `client.ovpn` via `kubectl exec`, patches the `remote` line, and creates a `client-ovpn` ConfigMap.
3. The client deployment mounts this ConfigMap — no kubectl-in-pod RBAC needed.
4. `capture.sh` starts tcpdump on the **server's** sniffer sidecar *before* restarting the client pod, guaranteeing the handshake is captured.
5. `classify.py` decodes opcodes from the pcap and prints a DPI verdict.

## DNS: the quiet failure mode

After the tunnel is up, try:

```bash
kubectl -n openvpn-lab exec deploy/openvpn-client -c ovpn-client -- \
  cat /config/client.ovpn | grep dhcp-option
```

You'll see the pushed DNS server (10.8.0.1) and the pushed search domain (`corp.internal`). If those pushes are missing or the client doesn't honour them, **every DNS query leaks to the host's resolver**. That's the DNS-leak failure mode from the blog post, reproducible in 30 seconds.

## Test assertions

| # | Assertion | How to check |
|---|-----------|--------------|
| 1 | k3d cluster `openvpn-lab` exists | `k3d cluster list \| grep -q openvpn-lab` |
| 2 | Deployments `openvpn-server`, `openvpn-client` Available | `kubectl -n openvpn-lab rollout status deploy/openvpn-server deploy/openvpn-client` |
| 3 | Tunnel completed: client logs contain `Initialization Sequence Completed` | `kubectl -n openvpn-lab logs deploy/openvpn-client -c ovpn-client \| grep -q 'Initialization Sequence Completed'` |
| 4 | `openvpn.pcap` exists and is non-empty (run `task capture` first) | `test -s ./openvpn.pcap` |
| 5 | `classify.py` verdict contains `OpenVPN` | `python3 classify.py ./openvpn.pcap \| grep -qi 'openvpn'` |

> Assertions 4–5 require `task capture` to have run first. The `test` task prints a warning (not a failure) if the pcap is absent.

## Cleanup

```bash
task cleanup
```

## Takeaway questions

1. Could you write a **WireGuard** classifier with the same approach? (Yes — UDP, fixed handshake shape, even more distinctive. That's Part 4's punchline, not a defense.)
2. What would you have to change about your threat model to take "VPN endpoint is inside the network and trusted" off the table? (That's Parts 5 and 6.)
3. Which part of this lab *isn't* representative of a production deploy? (Certs. Production deploys cert-based auth with 2FA, not PSK/TLS-crypt alone.)

## Next

→ [Part 4 — WireGuard: Why Simpler Won](../part4/) *(coming next)*

← [Part 2 — SSH and the Cryptographic Turn](../part2/)
