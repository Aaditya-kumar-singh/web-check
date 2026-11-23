# Web-Check behind Cloudflare Tunnel

This deployment builds **Web-Check from this GitHub fork** and serves it locally. The existing Cloudflare Tunnel can then publish it at `https://webcheck.aadityakumar.online`.

GitHub stores the code; it does **not** run this Node.js/Chromium application continuously. Your Windows PC (or another Docker host) must stay powered on to serve it. Cloudflare Tunnel can be free, and it doesn't require changing the existing LocalMCP server on port 8047.

## Prerequisites

- Docker Desktop installed and running with Linux containers
- A named Cloudflare Tunnel pointing at this machine
- Control of the `aadityakumar.online` domain in Cloudflare
- A **Cloudflare Access** self-hosted application allowing only your email to access `webcheck.aadityakumar.online`

**Create and test the Access policy before making the hostname public.** Web-Check has no built-in login. It can make HTTP requests, run browser checks, and inspect arbitrary public sites; do not expose it without an access policy.

## Start the application

From the repository root in PowerShell:

```powershell
docker compose -f deploy/cloudflare/compose.yaml up -d --build
```

Verify it responds locally:

```powershell
docker compose -f deploy/cloudflare/compose.yaml ps
Invoke-RestMethod http://127.0.0.1:3000/healthz
```

Expected: `status: ok` and, once routes initialize, `ready: true`.

## Connect the existing Cloudflare Tunnel

In Cloudflare Zero Trust, open **Networks → Tunnels** (or **Networking → Tunnels**) and choose your existing named tunnel. Add **a new** public hostname/application route:

| Setting | Value |
| --- | --- |
| Subdomain | `webcheck` |
| Domain | `aadityakumar.online` |
| Service type | `HTTP` |
| Service URL | `localhost:3000` |

Keep the existing `mcp2.aadityakumar.online → localhost:8047` route exactly as it is. Do not start another tunnel service, alter its token, or disable OAuth for LocalMCP.

Sign in through Cloudflare Access, then visit:

```text
https://webcheck.aadityakumar.online/check
```

If your intended domain differs, set `WEB_CHECK_ORIGIN` to its full `https://` URL before starting Compose. Cloudflare's route and Access application must use the same hostname.

## Security and operations

- The published listener binds only to `127.0.0.1:3000`; do not change it to `0.0.0.0` or publish port 3000 on your router.
- Rate limiting is enabled; `ports` and `trace-route` checks are disabled to reduce active probing. These checks can be re-enabled only for authorized assessments.
- `API_BLOCKED_HOSTS` blocks common private address patterns **as typed**, but is **not a security boundary** against DNS rebinding, redirects or host resolution. Cloudflare Access and host-level firewall controls remain necessary.
- Browser checks can load untrusted websites into Chromium. Keep Web-Check updated, and only scan targets you own or are authorized to test.
- No Cloudflare credentials, API keys, or tunnel tokens belong in Git. Keep them in your Cloudflare account or a local, gitignored configuration file.
- To update, pull the latest code, then run `docker compose -f deploy/cloudflare/compose.yaml up -d --build`.
- To stop only Web-Check: `docker compose -f deploy/cloudflare/compose.yaml down`. This does not stop LocalMCP or cloudflared.

**Current setup limitation:** Docker Desktop is not installed on this Windows machine, and the Cloudflare hostname/Access policy have not been created by this repository configuration. Both are required before the public site is available.

Upstream project: https://github.com/lissy93/web-check (MIT License).
