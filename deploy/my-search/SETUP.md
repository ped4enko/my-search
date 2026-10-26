# My Search — first-run notes

Companion to [`README.md`](./README.md). For a full VPS walkthrough, use the
bootstrap script from the repo root:

```bash
DOMAIN=search.example.com ACME_EMAIL=you@example.com sudo -E bash scripts/bootstrap-vps.sh
```

## What this bundle does

- Official `searxng/searxng` image + Valkey + optional Caddy (`--profile tls`)
- Instance name **My Search**, Ukrainian/English UI locales
- Limiter on (needs Valkey), image proxy on, `public_instance: false`
- Port `8080` bound to `127.0.0.1` by default; Caddy terminates TLS on 80/443

## After `docker compose --profile tls up -d`

```bash
docker compose ps
docker compose logs searxng | head -30   # should not show Valkey connection errors
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS 'http://127.0.0.1:8080/search?q=test&format=json' | head -c 300
```

Update: `docker compose pull && docker compose up -d`.  
Backup: `searxng/` + `.env` (volumes are caches only).

## Customize

Restart after edits: `docker compose restart searxng`.

| Area | File |
| --- | --- |
| Branding, engines, plugins, hostnames | `searxng/settings.yml` |
| Rate limits / pass_ip | `searxng/limiter.toml` + `.env` |
| Domain / secret / public URL | `.env` (from `.env.example`) |

See the table in `README.md` for exact keys.
