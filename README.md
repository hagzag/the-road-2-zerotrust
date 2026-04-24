# The Road to Zero Trust — Companion Labs

Hands-on k3d labs for the blog series **"From Trusted Wires to Zero Trust: A Practitioner's Evolution of Remote Access"** by [Haggai Philip Zagury (HagZag)](https://portfolio.hagzag.com).

Every post in the series ships a self-contained lab here. Labs run locally on [`k3d`](https://k3d.io) — no cloud account needed — so you can sniff packets, break things, and see for yourself why each evolution of remote access happened.

## Layout

```
practice/
├── part1/   From Trusted Wires to the Open Internet
├── part2/   SSH and the Cryptographic Turn
├── part3/   VPNs: OpenVPN, IPsec, and the TLS Tunnel
├── part4/   WireGuard: Why Simpler Won
├── part5/   Identity Is the New Perimeter (AuthN/AuthZ/MFA)
├── part6/   Zero Trust Networking: Identity Meets the Network
├── part7/   Compliance, Cloud, and Consulting from Anywhere  (no lab)
<!-- └── part8/   Epilogue: The Reverse Tunnel (ngrok / cloudflared / frp) -->
```

Each `practice/partN/` contains a `README.md`, Kubernetes manifests, and a `run.sh` / `cleanup.sh` pair.

## Prereqs (once, for the whole series)

- Docker
- [`k3d`](https://k3d.io) ≥ v5
- `kubectl` ≥ v1.28
- Wireshark (or `tshark`) for the packet-capture labs

## Posts

1. **[From Trusted Wires to the Open Internet](https://hagzag23.medium.com/from-trusted-wires-to-the-open-internet-43dfe7807d28)** — lab: [`practice/part1/`](./practice/part1/)
2. **[SSH and the Cryptographic Turn](https://portfolio.hagzag.com/blog/ssh-and-the-cryptographic-turn/)** — lab: [`practice/part2/`](./practice/part2/)
3. **[VPNs: OpenVPN, IPsec, and the TLS Tunnel](https://portfolio.hagzag.com/blog/vpns-openvpn-ipsec-and-the-tls-tunnel/)** — lab: [`practice/part3/`](./practice/part3/)
4. **WireGuard: Why Simpler Won** — lab: [`practice/part4/`](./practice/part4/)
5. **Identity Is the New Perimeter** — lab: [`practice/part5/`](./practice/part5/)
6. **Zero Trust Networking: Identity Meets the Network** — lab: [`practice/part6/`](./practice/part6/)
7. **Compliance, Cloud, and Consulting from Anywhere** — retrospective finale (no lab)
<!-- 8. **The Reverse Tunnel (Epilogue)** — ngrok / Cloudflare Tunnel / frp — lab: [`practice/part8/`](./practice/part8/) -->

## License

Labs are MIT-licensed unless noted otherwise. The blog text itself is © Haggai Philip Zagury and is cross-posted on [Medium](https://hagzag23.medium.com) and [portfolio.hagzag.com](https://portfolio.hagzag.com).
