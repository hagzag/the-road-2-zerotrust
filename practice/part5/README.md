# Part 5 — Identity Is the New Perimeter

**Companion lab for**: [Identity Is the New Perimeter: AuthN, AuthZ, MFA, and Why They Matter](https://portfolio.hagzag.com/blog/identity-is-the-new-perimeter/)
**Series**: [The Road to Zero Trust](../../README.md)
**Estimated time**: 5–15 minutes
**Prereqs**: Docker, [`k3d`](https://k3d.io), `kubectl`, `jq`, a modern browser with DevTools

## What you'll see

Stand up Keycloak on k3d, register an OIDC-protected demo app, walk the Authorization Code + PKCE flow end-to-end in your browser, enroll TOTP, decode the ID token, and watch what `aud` and `nonce` actually defend against.

By the end you'll have felt:

1. How identity replaces the VPN as the access boundary — the app is reachable on the cluster network, but useless without a valid token.
2. How the OIDC redirect dance actually works — every 302, every PKCE exchange, visible in DevTools.
3. What JWT claims (`iss`, `aud`, `exp`, `nonce`) actually prevent — replay, misbinding, expiry.

## Architecture

```
Browser ──► oauth2-proxy ──► demo-app (nginx)
               │
               └──► Keycloak (OIDC provider)
                      │
                      └──► Postgres (persistence)
```

- **oauth2-proxy** uses the in-cluster Keycloak service URL for token exchange and JWKS verification, but overrides `--login-url` to `localhost:8081` so browser redirects go through your port-forward.
- **Keycloak** runs in `start-dev` mode with health enabled.
- **No ingress** — everything is accessed via `kubectl port-forward`.

## Run it

```bash
task run            # cluster + Keycloak + realm bootstrap + app (fully automated)
task test           # verify all 6 assertions

# For the interactive browser demo, start port-forwards:
kubectl -n auth-lab port-forward svc/keycloak     8081:8080 &
kubectl -n auth-lab port-forward svc/oauth2-proxy 8080:4180 &

# Open http://localhost:8080 and log in with haggai / Pa55w0rd
# Keycloak admin: http://localhost:8081 (admin / Pa55w0rd)

# After login, decode your ID token:
./decode-token.sh <paste id_token>
```

## Test assertions

| # | Assertion | How to check |
|---|-----------|--------------|
| 1 | k3d cluster `auth-lab` exists | `k3d cluster list \| grep -q auth-lab` |
| 2 | Deployments `postgres`, `keycloak`, `demo-app`, `oauth2-proxy` Available | `kubectl -n auth-lab rollout status` |
| 3 | Keycloak health responds | `kubectl exec deploy/keycloak -- /bin/bash -c '... /dev/tcp/localhost/8080 ...'` (no curl in Keycloak image) |
| 4 | Realm `lab` bootstrapped | `test -f ./out/realm-bootstrapped` |
| 5 | User `haggai` exists in realm `lab` | `kcadm.sh` via `kubectl exec` (no curl in Keycloak image) |
| 6 | oauth2-proxy `/ping` responds | `kubectl exec deploy/demo-app -- wget ... oauth2-proxy:4180/ping` (oauth2-proxy is distroless — no shell) |

## What to look for in DevTools

Open the Network tab **before** clicking login. You'll see the redirect dance:

1. `GET /oauth2/start` on the proxy → `302` to Keycloak's `/auth` endpoint.
2. The URL carries `response_type=code`, `code_challenge=<sha256>`, `code_challenge_method=S256`, `state=<random>`, `nonce=<random>`.
3. You authenticate, Keycloak `302`s back to `/oauth2/callback?code=...&state=...`.
4. The proxy makes a **server-to-server** `POST /token` with the `code` + `code_verifier`.
5. Keycloak responds with `id_token`, `access_token`, `refresh_token`.

Grab the `id_token` from the cookies (or the `/oauth2/userinfo` endpoint) and feed it to `./decode-token.sh`.

## URL strategy explained

oauth2-proxy lives inside the cluster and needs to reach Keycloak for token exchange and JWKS verification — but the browser also needs to reach Keycloak for the auth redirect. These are two different network paths:

- **In-cluster** (token exchange, JWKS): `http://keycloak.auth-lab.svc.cluster.local:8080/realms/lab`
- **Browser** (auth redirect): `http://localhost:8081/realms/lab/protocol/openid-connect/auth` (via port-forward)

oauth2-proxy is configured with `--oidc-issuer-url` pointing to the in-cluster URL for discovery + token exchange, and `--login-url` overridden to `localhost:8081` for browser redirects.

## Optional: TOTP and WebAuthn

In the Keycloak admin UI (`http://localhost:8081`) → realm `lab` → Authentication → Required Actions → enable **Configure OTP** and **Webauthn Register**. Then in User Details for `haggai`, set a required action. Next login, Keycloak walks you through enrollment.

The point: log out, clear cookies, try to replay the stolen `id_token` against oauth2-proxy. The flow fails because the `nonce` is bound to a session that no longer exists, and the `aud` check catches tokens issued for a different client.

## File layout

```
practice/part5/
├── Taskfile.yaml           ← task run / bootstrap-realm / decode-token / test / cleanup
├── README.md
├── manifests/
│   ├── namespace.yaml
│   ├── keycloak.yaml       ← Postgres + Keycloak (health enabled)
│   └── app.yaml            ← demo-app (nginx) + oauth2-proxy (in-cluster issuer + login-url override)
├── bootstrap-realm.sh      ← realm + client + user via kubectl exec (no port-forward needed)
├── run.sh                  ← full setup + auto-bootstrap
├── decode-token.sh         ← decode + validate JWT claims
└── cleanup.sh
```

## Cleanup

```bash
task cleanup
```

## Further reading

- [Keycloak — Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/index.html)
- [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) — the OIDC client in this lab
- [PKCE explained](https://datatracker.ietf.org/doc/html/rfc7636)
- [jwt.io](https://jwt.io/) — paste the `id_token` and read it live

## Next

→ [Part 6 — Zero Trust Networking: Identity Meets the Network](../part6/)

← [Part 4 — WireGuard: Why Simpler Won](../part4/)
