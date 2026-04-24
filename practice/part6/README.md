# Part 6 — Zero Trust Networking: Identity Meets the Network

Companion lab for **[Zero Trust Networking: Identity Meets the Network](https://portfolio.hagzag.com/blog/zero-trust-networking-identity-meets-the-network/)** (Part 6 of the *Road to Zero Trust* series).

## What you'll see

A self-hosted ZTNA-style stack on a single-node `k3d` cluster:

- **Keycloak** — the identity provider (OIDC issuer).
- **oauth2-proxy** — the identity-aware proxy. Every request to the app has to come with a valid session tied to a **Keycloak-authenticated identity** *and* that identity has to be on an **allowlist**. Two distinct checks: authentication (Keycloak says who you are) and authorization (the proxy decides if *this* identity is allowed to reach *this* app).
- **demo-app** — a plain nginx. It has no authentication of its own. Access is governed entirely by what sits in front of it.
- **lateral-move.sh** — launches a throwaway pod on the same cluster network and shows that IP reachability is not access.

This maps to the four-part model from the post:

| Model piece | Lab piece                                           |
|-------------|-----------------------------------------------------|
| Application | `demo-app` (nginx Service in `zt-lab`)              |
| Policy      | oauth2-proxy `--authenticated-emails-file` allowlist|
| Tunnel      | your kubectl port-forward (local TLS-free stand-in) |
| Route       | oauth2-proxy `--upstream` to the Service DNS name   |

## Prereqs

- Docker
- [`k3d`](https://k3d.io) ≥ v5
- `kubectl` ≥ v1.28
- `jq`, `curl`

## Run it

```bash
./run.sh

# In two other terminals:
kubectl -n zt-lab port-forward svc/keycloak     8081:8080
kubectl -n zt-lab port-forward svc/oauth2-proxy 8080:4180

./bootstrap-realm.sh
```

Seeded users (both password `Pa55w0rd`):

- `alice@example.com` — on the allowlist → gets into the app.
- `bob@example.com` — Keycloak authenticates her, the proxy **denies** her at policy.

Open http://localhost:8080 and log in as each.

### Lateral-move demo

```bash
./lateral-move.sh
```

This deploys a rogue `curl` pod inside the `zt-lab` namespace and hits:

1. `http://oauth2-proxy.zt-lab.svc.cluster.local:4180/` → **302 to the login page**, because the rogue pod has no session. This is what a compromised workload on the cluster network runs into.
2. `http://demo-app.zt-lab.svc.cluster.local/` → the nginx responds, because network reachability isn't gated by this lab. In a real deployment you'd add a `NetworkPolicy` so only `oauth2-proxy` can talk to `demo-app`. Defense in depth: identity at L7, network at L3/L4.

The point isn't that the backend is exposed. The point is that in a VPN-shaped world, lateral movement gets you the app; in a ZT-shaped world, lateral movement gets you a login page.

## Clean up

```bash
./cleanup.sh
```

Deletes the k3d cluster and the `out/` scratch directory.

## Not shown here (on purpose)

- Device posture. In a real ZTNA stack, the Policy piece also evaluates EDR signals from the endpoint. Simulating that faithfully needs a real agent; the lab sticks to identity.
- Continuous re-evaluation mid-session. oauth2-proxy can hit `oidc_session_refresh` but the cadence matters less than the concept.
- A proper TLS-terminating tunnel. The `localhost:8080` port-forward stands in for "the Tunnel" from the four-part model. A production stack terminates TLS at the edge and carries the traffic over something like WireGuard (Part 4).

## Files

```
practice/part6/
├── README.md              # this file
├── run.sh                 # create cluster + deploy stack
├── bootstrap-realm.sh     # seed realm, client, alice (allowed) + bob (denied)
├── lateral-move.sh        # rogue pod -> 302 at proxy; reachable at nginx
├── cleanup.sh             # tear it all down
└── manifests/
    ├── namespace.yaml     # ns: zt-lab
    ├── keycloak.yaml      # Postgres + Keycloak 24 dev-mode
    └── app.yaml           # demo-app nginx + oauth2-proxy + allowlist ConfigMap
```
