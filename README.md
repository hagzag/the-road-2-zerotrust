# The Road to Zero Trust

> *From Trusted Wires to Zero Trust: A Practitioner's Evolution of Remote Access*

A 7-part blog series by [Haggai Philip Zagury](https://github.com/hagzag) tracing the full arc of remote access — from ARPANET cleartext to Zero Trust Networking — with k3d labs you can actually run.

## The Series

| # | Title | Core tech |
|---|-------|-----------|
| 1 | From Trusted Wires to the Open Internet | Telnet/rsh/rlogin, ARPANET, hosts.txt → DNS |
| 2 | SSH and the Cryptographic Turn | SSH, bastions, SSH CAs, SSHFP |
| 3 | VPNs: OpenVPN, IPsec, and the TLS Tunnel | OpenVPN, IPsec/IKEv2, DPI fingerprinting |
| 4 | WireGuard: Why Simpler Won | WireGuard, mesh overlays (Tailscale/Headscale) |
| 5 | Identity Is the New Perimeter | OIDC/OAuth/SAML, MFA, FIDO2, DevOps identity |
| 6 | Zero Trust Networking: Identity Meets the Network | ZTNA, Cloudflare Access, Pomerium, device posture |
| 7 | Compliance, Cloud, and Consulting from Anywhere | SOC 2/FIPS/FedRAMP, hyperscaler ZT offerings |

Posts publish in order. No backdating.

## Four Threads Running Through Every Post

- **OSI ladder** — every technology explicitly placed on its layer(s)
- **Trust-boundary migration** — physical → network → host → identity
- **DNS as connective tissue** — naming, discovery, leaks, and policy enforcement at each era
- **Anchor client story** — one anonymized real engagement per post

## Practice

Hands-on labs live under `practice/`. Each part has its own folder with a `README.md` (step-by-step guide) and runnable scripts.

| Part | Lab | What you build |
|------|-----|----------------|
| 1 | [practice/part1](./practice/part1/) | Telnet + tcpdump sniffer pod — read your own credentials in cleartext |

Labs build on each other. Part 1's k3d cluster (`trusted-wire`) is reused in Part 2.

Prerequisites: `k3d`, `kubectl`, `wireshark`/`tshark`. Parts 4+ also need `iperf3`.

## Cross-posted to

- [Medium](https://medium.com/@hagzag23)
- Hugo static site

## License

Content © Haggai Philip Zagury. Labs and code snippets MIT.
