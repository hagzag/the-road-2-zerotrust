# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, Copilot, etc.) when working in this repository.

## Purpose

This repo hosts the written content for **"From Trusted Wires to Zero Trust: A Practitioner's Evolution of Remote Access"** — a 7-part blog series by Haggai Philip Zagury (HagZag).

Series plan lives at: `/Users/hagzag/Projects/hagzag/portfolio/series/zerotrust/remote-access-series-plan.md`

**Always read the plan file before drafting any post.**

## Series Structure

7 posts, published in order (no backdating, no skipping):

| Part | Slug | Core tech |
|------|------|-----------|
| 1 | `from-trusted-wires-to-the-open-internet` | Cleartext protocols, ARPANET, hosts.txt → DNS |
| 2 | `ssh-and-the-cryptographic-turn` | SSH, bastions, SSH CAs, SSHFP |
| 3 | `vpns-openvpn-ipsec-and-the-tls-tunnel` | OpenVPN, IPsec/IKEv2, DPI fingerprinting |
| 4 | `wireguard-why-simpler-won` | WireGuard, mesh overlays (Tailscale/Headscale) |
| 5 | `identity-is-the-new-perimeter` | OIDC/OAuth/SAML, MFA, FIDO2, DevOps identity |
| 6 | `zero-trust-networking-identity-meets-the-network` | ZTNA, Cloudflare/Pomerium, device posture |
| 7 | `compliance-cloud-and-consulting-from-anywhere` | SOC2/FIPS/FedRAMP, hyperscaler ZT, wrap-up |

Source decks for Parts 5 and 6 are `.pptx` files — use the `pptx` skill to parse them.

## Post Structure (required for every post)

1. Hugo front matter with **current date** in ISO 8601, slug per table above
2. Hook opening — not a definition
3. TL;DR section
4. **Provenance callout directly under TL;DR** (see plan for exact wording)
5. Body (~1200–1500 words prose)
6. 2–4 `IMAGE_PROMPT:` blocks
7. k3d lab section with runnable commands
8. 1–3 code/config snippets
9. Social snippets: LinkedIn / X / Facebook / Instagram
10. Medium + Hugo cross-post footer

## Four Cross-Cutting Threads

Every post must weave all four:
- **OSI ladder** — explicitly place each technology on its layer(s)
- **Trust-boundary migration** — physical → network → host → identity (advances one step per post)
- **DNS as connective tissue** — each tech's DNS story (see plan for per-post specifics)
- **Anchor client story** — anonymized per the client map in the plan

## Output Location

Save drafts to:
```
/sessions/tender-busy-hopper/mnt/outputs/<current-date>-<slug>.md
```

Present for user review before moving to the next post.

## Anchor Client Anonymization

Clients are anonymized in public posts. The mapping is in the plan file. Never use real client names in any file committed to this repo.

## k3d Labs

Every post ships a k3d lab. Labs:
- Run locally with `k3d` + standard tools
- Let readers capture packets and debug
- Are cumulative — Part 6 builds on Part 5's Keycloak deployment
- Live in a shared lab repo (branches or folders per part) so readers can progress linearly
