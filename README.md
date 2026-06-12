# CSAT + Live Support Appliance

One host, two products, automatic HTTPS — **CSAT** (multi-tenant survey + analytics) and
**Live Support** (WebRTC video/voice/chat) behind **Caddy**, via `docker compose`.

```
                          ┌─ csat.<domain>         → csat:8080         (multi-tenant)
Internet :443 ── Caddy ───┤
   (auto Let's Encrypt)   └─ live-support.<domain> → live-support:8000 (multi-tenant)
```

The apps speak plain HTTP on the internal Docker network; only Caddy is exposed (80/443).
WebRTC media is peer-to-peer / Cloudflare TURN, so **no UDP port ranges** are needed. Each app
keeps its data (one SQLite DB per tenant) on a named volume.

## Deploy

A small box is plenty — an AWS `t4g.small` (ARM/Graviton; the images are multi-arch) is free-tier
through 2026. Open inbound **22 (your IP), 80, 443** only.

```sh
# on the host (Docker + compose installed)
git clone <this-repo> && cd instantaiguru-appliance
cp .env.example .env && $EDITOR .env          # hostnames, secrets, Cloudflare TURN
# point DNS A records for $CSAT_HOST and $LS_HOST at this host, then:
docker compose up -d
```

Caddy obtains certificates for both hostnames automatically on first request. Check:
`docker compose logs -f caddy` and `curl -fsS https://$CSAT_HOST/healthz` → `ok`.

## Onboarding a CSAT tenant (self-serve)

The platform holds `CSAT_CRYPTO_SECRET` (the master key) and onboards customers without ever
sharing it. From the platform's integration card:

```sh
# POST a signed provisioning token; the reply has the admin invite link.
curl -fsS -X POST "https://$CSAT_HOST/provision?t=<signed-token>"
#  -> { "ref": "acme.com", "invite_url": "https://csat.<domain>/invite?t=…&ref=acme.com" }
```

Build the token with `csat -mint-tenant -ref acme.com` or the `provisionUrl` / `provision_url`
helpers in the csat repo's `integrations/`. Hand the `invite_url` to the customer: they set their
email + password and become the tenant's first admin. Re-provisioning is the forgot-password
break-glass (an existing email reclaims the account). Each tenant then self-edits its survey
(visual designer) and branding in the CSAT admin UI.

## Configuration

- **`.env`** — hostnames, the CSAT master secret, Live Support admin/TURN settings, image tags.
- **`csat/config.toml`** — CSAT runs multi-tenant, behind Caddy (`secure_cookies = true`,
  `trust_proxy` limited to the internal network). Edit branding/TTLs here.
- **`Caddyfile`** — one `reverse_proxy` block per product; certs are automatic.

## Updating

```sh
docker compose pull && docker compose up -d   # roll to the latest images
```
Pin specific releases with `CSAT_TAG` / `LS_TAG` in `.env`. App schemas migrate automatically on
start; tenant data persists on the volumes.

## Images

- `ghcr.io/ronpinkas/csat` — built + pushed by the csat repo's release CI (multi-arch).
- `ghcr.io/anthonyicuracao/live-support` — same, from the live-support repo.

Both are public, so the host needs no registry login.

## Credits

This appliance bundles two self-contained products, each developed and maintained in its
own repository — the appliance itself is just the glue (Caddy config, `docker compose`,
onboarding docs):

- **CSAT** — multi-tenant survey + analytics — [github.com/ronpinkas/csat](https://github.com/ronpinkas/csat) · MIT.
- **Live Support** — WebRTC voice / video / chat + Web Push — [github.com/anthonyicuracao/live-support](https://github.com/anthonyicuracao/live-support) · MIT.

## License

MIT — see [LICENSE](LICENSE). © 2026 Ron Pinkas. The bundled products are licensed
separately in their own repositories (linked above).
