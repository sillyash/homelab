# EX-AMIGA

Band website for EX-AMIGA ([sillyash/examiga-web](https://github.com/sillyash/examiga-web)).
The frontend is on GitHub Pages at `examigaband.com` (deployed by the repo's Actions
workflow). Only the Flask API runs here, at `api.examigaband.com`.

## DNS (Cloudflare, `examigaband.com` zone)

The GitHub Pages records are **DNS only** (grey cloud) — GitHub can't issue its cert
behind the proxy. `api` is the exception: it's a [Cloudflare Tunnel](../cloudflared/README.md)
route, created from the tunnel's Public Hostnames tab (proxied, orange cloud).

| Type | Name | Content |
|---|---|---|
| A | `@` | `185.199.108.153`, `.109.153`, `.110.153`, `.111.153` (4 records) |
| CNAME | `www` | `sillyash.github.io` |
| CNAME | `api` | `<tunnel-id>.cfargotunnel.com` (managed by the tunnel route) |
| TXT | `_github-pages-challenge-sillyash` | value from GitHub → Settings → Pages |

## Layout

Same split as dropservice: you own the git checkout, root owns the deployed copy,
and the service can only write its DB.

| Path | Owner | What |
|---|---|---|
| `~/examiga-web` | you | git checkout: pull and edit here, never as root |
| `/opt/examiga-api` | root | deployed copy of `api/` + `.venv` + uv's Python (`REVISION` = commit) |
| `/var/lib/examiga/examiga.db` | www-data | SQLite DB (systemd `StateDirectory`, via `EXAMIGA_DB_PATH`) |

## Deploy

First install, from a homelab checkout on the Pi:

```bash
git clone git@github.com:sillyash/examiga-web.git ~/examiga-web
sudo services/examiga/deploy.sh --seed   # rsync api/, uv sync, install unit, seed

sudo certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d api.examigaband.com
sudo cp services/nginx/sites-available/examiga /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/examiga /etc/nginx/sites-enabled/examiga
sudo nginx -t && sudo systemctl reload nginx
```

`deploy.sh` refuses to deploy uncommitted changes in `api/`, and it reads git only as
`$SUDO_USER`, so root never touches the repo.

## Update

```bash
git -C ~/examiga-web pull
sudo ~/homelab/services/examiga/deploy.sh
```

To change tour dates, edit `api/seed.py`, commit and push, pull on the Pi, then run
`deploy.sh --seed`. Every seed run replaces the whole `tour_dates` table.

Back up the DB with
`sudo sqlite3 /var/lib/examiga/examiga.db ".backup /path/to/examiga-$(date +%F).db"`.

## Migrating from the old `/opt/examiga-web` checkout

The old setup was a `www-data`-owned git clone with the DB in `api/`. Moving to the new layout is a one-time step:

```bash
git clone git@github.com:sillyash/examiga-web.git ~/examiga-web
sudo systemctl stop examiga-api
sudo install -d -o www-data -g www-data /var/lib/examiga
sudo cp -a /opt/examiga-web/api/examiga.db /var/lib/examiga/
sudo mv /opt/examiga-web /opt/examiga-web.old   # rollback copy
sudo ~/homelab/services/examiga/deploy.sh
# once it checks out:
sudo rm -rf /opt/examiga-web.old
```
