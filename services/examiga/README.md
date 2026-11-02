# EX-AMIGA

Band website for EX-AMIGA ([sillyash/examiga-web](https://github.com/sillyash/examiga-web)).
The frontend is on GitHub Pages at `examigaband.com` (deployed by the repo's Actions
workflow). The Django app runs here: the public API at `api.examigaband.com` and the
content admin at `admin.examigaband.com` (one Gunicorn service, two nginx vhosts).

## DNS (Cloudflare, `examigaband.com` zone)

The GitHub Pages records are **DNS only** (grey cloud) — GitHub can't issue its cert
behind the proxy. `api` and `admin` are the exception: they're [Cloudflare Tunnel](../cloudflared/README.md)
routes, created from the tunnel's Public Hostnames tab (proxied, orange cloud). `admin`
also sits behind the `homelab-admin` Cloudflare Access policy.

| Type | Name | Content |
|---|---|---|
| A | `@` | `185.199.108.153`, `.109.153`, `.110.153`, `.111.153` (4 records) |
| CNAME | `www` | `sillyash.github.io` |
| CNAME | `api` | `<tunnel-id>.cfargotunnel.com` (managed by the tunnel route) |
| CNAME | `admin` | `<tunnel-id>.cfargotunnel.com` (managed by the tunnel route) |
| TXT | `_github-pages-challenge-sillyash` | value from GitHub → Settings → Pages |

## Layout

Same split as dropservice: you own the git checkout, root owns the deployed copy,
and the service can only write its DB.

| Path | Owner | What |
|---|---|---|
| `~/examiga-web` | you | git checkout: pull and edit here, never as root |
| `/opt/examiga-api` | root | deployed copy of `api/` + `.venv` + uv's Python (`REVISION` = commit) |
| `/etc/examiga/config.env` | root | non-secret settings, copied from [`config.env`](config.env) on each deploy |
| `/etc/examiga/secret.env` | root, 600 | `EXAMIGA_SECRET_KEY`, generated once by `deploy.sh`, never overwritten |
| `/var/lib/examiga/db.sqlite3` | www-data, 640 | SQLite DB (systemd `StateDirectory`, via `EXAMIGA_DB_PATH`) |
| `/var/lib/examiga/staticfiles` | www-data | admin CSS/JS from `collectstatic`, served by nginx |
| `/var/lib/examiga/examiga.db` | www-data | old Flask DB, kept for rollback only |

## Deploy

First install, from a homelab checkout on the Pi:

```bash
git clone git@github.com:sillyash/examiga-web.git ~/examiga-web
sudo services/examiga/deploy.sh   # rsync api/, uv sync, env files, migrate, collectstatic, unit

for host in api admin; do
  sudo certbot certonly --dns-cloudflare \
    --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
    -d "$host.examigaband.com"
done
sudo cp services/nginx/sites-available/examiga /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/examiga /etc/nginx/sites-enabled/examiga
sudo nginx -t && sudo systemctl reload nginx

sudo services/examiga/manage.sh createsuperuser   # admin login
```

On the first run, `migrate` creates the tables and loads `api/backup/*.json` (the
data migration `shows/0002_backup_data`). Later runs only apply new migrations, so
data edited in the admin is never overwritten.

`deploy.sh` refuses to deploy uncommitted changes in `api/`, and it reads git only as
`$SUDO_USER`, so root never touches the repo. It deploys whatever branch is checked
out in `~/examiga-web`.

## Update

```bash
git -C ~/examiga-web pull
sudo ~/homelab/services/examiga/deploy.sh
```

Tour dates and shoutouts are edited at <https://admin.examigaband.com/admin/>.
`manage.sh` runs any other Django command as `www-data` with the service environment
(`sudo ./manage.sh changepassword <user>`, `sudo ./manage.sh shell`, ...).

The api vhost returns 404 for `/admin/` and `/static/`, so the admin is only
reachable through Cloudflare Access. nginx forwards `X-Forwarded-Proto: https`
(Django redirects plain HTTP and builds https cursor links) and
`X-Forwarded-For: $http_cf_connecting_ip` (the per-IP shoutout throttle; nginx's own
`$remote_addr` is always cloudflared).

Back up the DB with
`sudo sqlite3 /var/lib/examiga/db.sqlite3 ".backup /path/to/examiga-$(date +%F).db"`.

## Rollback to Flask

The Flask DB (`/var/lib/examiga/examiga.db`) was left untouched by the Django cutover
on 2026-11-02 (a copy is also in `~/examiga-pre-django-2026-11-02.db`). Shoutouts
posted after the cutover only exist in `db.sqlite3`.

```bash
git -C ~/homelab checkout <pre-django-rev> -- services/examiga services/systemd/examiga-api.service services/nginx/sites-available/examiga
git -C ~/examiga-web checkout main
sudo ~/homelab/services/examiga/deploy.sh
sudo cp ~/homelab/services/nginx/sites-available/examiga /etc/nginx/sites-available/
sudo nginx -t && sudo systemctl reload nginx
```

The frontend must be redeployed from `main` too (Actions → Deploy to GitHub Pages).
