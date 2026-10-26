# My Search — personal SearXNG instance

A minimal, self-contained deployment bundle for a private
[SearXNG](https://github.com/searxng/searxng) metasearch instance.
It uses the official upstream container image; this folder does not replace
the SearXNG source tree in the repo root.

```
deploy/my-search/
├── docker-compose.yml   # searxng + valkey (+ caddy via `--profile tls`)
├── .env.example         # copy to .env; secret, base URL, domain
├── Caddyfile            # HTTPS reverse proxy (Let's Encrypt)
├── README.md
└── searxng/
    ├── settings.yml     # instance config (overrides upstream defaults)
    ├── limiter.toml     # bot protection / rate limiting
    └── favicons.toml    # favicon proxy cache (search.favicon_resolver)
```

VPS one-shot bootstrap (from the repo root, after clone):

```bash
DOMAIN=search.example.com ACME_EMAIL=you@example.com sudo -E bash scripts/bootstrap-vps.sh
```

## 1. Deploy on a VPS

Requirements: Linux VPS (1 vCPU / 1 GB RAM is enough), Docker Engine with the
Compose plugin, a DNS `A`/`AAAA` record pointing at the VPS if you want HTTPS.

```bash
# on the VPS
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 openssl
git clone https://github.com/ped4enko/my-search.git && cd my-search/deploy/my-search

cp .env.example .env
sed -i "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=$(openssl rand -hex 32)|" .env
nano .env        # set SEARXNG_BASE_URL, DOMAIN, ACME_EMAIL

# plain HTTP on 127.0.0.1:8080 (behind your own nginx/traefik)
docker compose up -d

# or with built-in HTTPS (ports 80/443 must be free)
docker compose --profile tls up -d
```

Check:

```bash
docker compose ps
curl -fsS http://127.0.0.1:8080/healthz          # -> OK
curl -fsS 'http://127.0.0.1:8080/search?q=test&format=json' | head -c 300
docker compose logs -f searxng                   # first start prints the version
```

Update:

```bash
docker compose pull && docker compose up -d
```

Backup: the `searxng/` folder and `.env`. Volumes only hold caches.

## 2. Customize

Every change below is a file edit followed by `docker compose restart searxng`.

| What | Where | Key |
| --- | --- | --- |
| Instance name | `searxng/settings.yml` | `general.instance_name` |
| Footer links | `searxng/settings.yml` | `brand.custom.links` |
| Contact / privacy links | `searxng/settings.yml` | `general.contact_url`, `general.privacypolicy_url` |
| Light/dark default | `searxng/settings.yml` | `ui.theme_args.simple_style` (`auto`, `light`, `dark`, `black`) |
| UI language | `searxng/settings.yml` | `ui.default_locale` (`""` = browser, `uk`, `en`) and `locales` |
| Search language default | `searxng/settings.yml` | `search.default_lang`, `search.languages` |
| Safe search | `searxng/settings.yml` | `search.safe_search` (0/1/2) |
| Enable/disable an engine | `searxng/settings.yml` | `engines: - name: <engine>` + `disabled: true/false` |
| Remove an engine entirely | `searxng/settings.yml` | `use_default_settings.engines.remove` |
| Plugins | `searxng/settings.yml` | `plugins.<module>.active` |
| Domain re-ranking / rewrite | `searxng/settings.yml` | `hostnames.high_priority`, `low_priority`, `replace`, `remove` |
| Rate limiting | `.env` + `searxng/limiter.toml` | `SEARXNG_LIMITER`, `[botdetection.ip_lists].pass_ip`, `link_token` |
| JSON API on/off | `searxng/settings.yml` | `search.formats` |

Engine names and shortcuts: `docker compose exec searxng cat /usr/local/searxng/searx/settings.yml`
or the upstream [settings.yml](https://github.com/searxng/searxng/blob/master/searx/settings.yml).
Engine health for a running instance: `http://<host>/stats` and `/stats/errors`.

### Custom logo / favicon

The simple theme reads images from `searx/static/themes/simple/img/`. Without
rebuilding the image you can bind-mount replacements:

```yaml
# docker-compose.yml -> services.searxng.volumes
- ./branding/searxng.svg:/usr/local/searxng/searx/static/themes/simple/img/searxng.svg:ro
- ./branding/favicon.svg:/usr/local/searxng/searx/static/themes/simple/img/favicon.svg:ro
- ./branding/favicon.png:/usr/local/searxng/searx/static/themes/simple/img/favicon.png:ro
```

For deeper changes (templates, CSS) edit this fork's
`searx/templates/simple/` and `client/simple/`, then build with
`container/Dockerfile`.

### Private engines

Add `tokens: ["<secret>"]` to an engine entry; it then only answers when the
user set the same token in Preferences → Engines. Useful for engines that hit
your own services (Gitea, Nextcloud, Jellyfin...).

## 3. Browser integration

OpenSearch descriptor is served at `/opensearch.xml`; Firefox and Chromium
pick it up automatically when you add `https://<DOMAIN>/search?q=%s` as a
search engine.
