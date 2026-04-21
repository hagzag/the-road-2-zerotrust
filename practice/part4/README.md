# Part 4 — WireGuard: Why Simpler Won

**Companion lab for**: [WireGuard: Why Simpler Won](https://portfolio.hagzag.com/blog/wireguard-why-simpler-won/)
**Series**: [The Road to Zero Trust](../../README.md)
**Estimated time**: 5–10 minutes
**Prereqs**: Docker, [`k3d`](https://k3d.io), `kubectl`, `wg` (wireguard-tools)

## What you'll see

Two WireGuard peers running in k3d:

- `peer-a` — WireGuard at 10.99.0.1, UDP/51820
- `peer-b` — WireGuard at 10.99.0.2, UDP/51820

You bring up the cluster, watch them handshake, ping across the tunnel, run `iperf3` to see the throughput, and capture the handshake to see how small it actually is on the wire.

By the end you'll have felt two things:

1. How **little** it takes to stand up an encrypted tunnel compared to OpenVPN (Part 3) — two keypairs, eight lines of config per side.
2. How the handshake is still **detectable** on the wire — even though it's just two tiny UDP packets, that's enough for DPI. That's why Part 5 moves to identity.

## Run it

```bash
task run          # build image, generate keys, create cluster, deploy peers
task test         # verify all 5 assertions
task bench        # iperf3 throughput comparison (tunnel vs. direct)
task capture      # capture WireGuard handshake → ./wg.pcap
task cleanup      # tear down
```

### Manual exploration

```bash
# Confirm the tunnel is up
kubectl exec -n wg-lab deploy/peer-a -- wg show

# Ping across the tunnel
kubectl exec -n wg-lab deploy/peer-a -- ping -c3 10.99.0.2

# Inspect the config that was generated
cat out/wg0-a.conf
```

## Test assertions

| # | Assertion | How to check |
|---|-----------|--------------|
| 1 | k3d cluster `wg-lab` exists | `k3d cluster list \| grep -q wg-lab` |
| 2 | Deployments `peer-a`, `peer-b` Available | `kubectl -n wg-lab rollout status deploy/peer-a deploy/peer-b` |
| 3 | WireGuard interface up on peer-a | `kubectl exec -n wg-lab deploy/peer-a -- wg show wg0` exits 0 |
| 4 | Recent handshake (< 3 min ago) | `wg show wg0 latest-handshakes` timestamp within 180s |
| 5 | Ping peer-b from peer-a across tunnel | `kubectl exec -n wg-lab deploy/peer-a -- ping -c3 -W2 10.99.0.2` |

## How it works

1. `run.sh` builds a custom Alpine image with `wireguard-tools`, `iperf3`, `tcpdump`, and `ping` baked in.
2. Generates two keypairs with `wg genkey` and renders a `wg0.conf` per peer.
3. Loads the configs as ConfigMaps, deploys both peers with `privileged: true` (needed to create the `wg0` interface).
4. The entrypoint parses `wg0.conf` and brings up WireGuard with `ip link add` + `wg set` — no `wg-quick` needed.
5. Persistent keepalive ensures the tunnel stays up even through NAT.

## Why this lab is so short

That's the point. The OpenVPN lab in [part3](../part3/) needs a PKI, a server config with dozens of directives, and an init container just to scaffold the CA. WireGuard is two keypairs and eight lines of config per side. The lab is short because the protocol is.

## Capture details

`capture.sh` starts tcpdump on peer-a, then bounces peer-b's wg0 interface to force a fresh handshake. You'll see two packets — a 148-byte initiator handshake and a 92-byte responder — before any data flows. Open the pcap in Wireshark and filter on `udp.port == 51820`.

## File layout

```
practice/part4/
├── Dockerfile              ← Alpine + wireguard-tools + iperf3 + tcpdump + ping
├── entrypoint.sh           ← parses wg0.conf, brings up wg0 with ip + wg commands
├── Taskfile.yaml           ← task run / bench / capture / test / cleanup
├── README.md
├── manifests/
│   ├── namespace.yaml
│   └── wg-peers.yaml       ← peer-a + peer-b Deployments + Services
├── run.sh                  ← build image, keys, ConfigMaps, deploy
├── bench.sh                ← iperf3 tunnel vs. direct comparison
├── capture.sh              ← restart + tcpdump → ./wg.pcap
└── cleanup.sh
```

## Further reading

- [WireGuard whitepaper](https://www.wireguard.com/papers/wireguard.pdf) — Donenfeld, 2017
- [Noise Protocol Framework](https://noiseprotocol.org/)
- [Tailscale — How NAT traversal works](https://tailscale.com/blog/how-nat-traversal-works)

## Next

→ [Part 5 — Identity Is the New Perimeter](../part5/) *(coming next)*

← [Part 3 — VPNs: OpenVPN, IPsec, and the TLS Tunnel](../part3/)
