# FiiReFLY

Django REST API for the FiiReFLY site ([sillyash/Krokodiile](https://github.com/sillyash/Krokodiile),
`api/`). The frontend is on GitHub Pages at `https://sillyash.com/Krokodiile/`
(deployed by the repo's Actions workflow on version tags). The API runs here at
`fiirefly-api.sillyash.com`: one Gunicorn service, one tunnel-only nginx vhost.

The hostname is `fiirefly-api`, not `api.fiirefly`: Cloudflare's free Universal SSL
only covers one level of subdomain (`*.sillyash.com`), so a two-level name has no
edge cert when proxied. It still shares the `sillyash.com` site with the frontend,
which the session cookie (Arise Connect login) needs.

## DNS (Cloudflare, `sillyash.com` zone)

`fiirefly-api` is a [Cloudflare Tunnel](../cloudflared/README.md) route, created
from the tunnel's Public Hostnames tab (proxied CNAME to `<tunnel-id>.cfargotunnel.com`),
service `https://127.0.0.1:8443`, Origin Server Name `fiirefly-api.sillyash.com`.
No Cloudflare Access: it's a public API, and the Django admin (`/admin/`) is protected
by its own login plus an nginx rate limit (`fiirefly_login`, 5 req/min, burst 5).

## Layout

Same split as examiga: you own the git checkout, root owns the deployed copy, and
the service can only write its DB and static files.

| Path | Owner | What |
|---|---|---|
| `~/Krokodiile` | you | git checkout: pull and edit here, never as root |
| `/opt/fiirefly-api` | root | deployed copy of `api/` + `.venv` (`REVISION` = commit) |
| `/etc/fiirefly/config.env` | root | non-secret settings, copied from [`config.env`](config.env) on each deploy |
| `/etc/fiirefly/secret.env` | root, 600 | `FIIREFLY_SECRET_KEY` (generated once by `deploy.sh`) + Arise Connect client id/secret (filled by hand), never overwritten |
| `/var/lib/fiirefly/db.sqlite3` | www-data, 640 | SQLite DB (systemd `StateDirectory`, via `FIIREFLY_DB_PATH`) |
| `/var/lib/fiirefly/staticfiles` | www-data | admin CSS/JS from `collectstatic`, served by nginx |

Gunicorn listens on `127.0.0.1:5001` with one worker: DRF's livre d'or throttle
lives in process memory.

## Deploy

First install, from a homelab checkout on the Pi:

```bash
git clone git@github.com:sillyash/Krokodiile.git ~/Krokodiile
sudo services/fiirefly/deploy.sh   # rsync api/, uv sync, env files, migrate, collectstatic, unit

sudo certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d fiirefly-api.sillyash.com
sudo cp services/nginx/conf.d/rate-limit.conf /etc/nginx/conf.d/
sudo cp services/nginx/sites-available/fiirefly /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/fiirefly /etc/nginx/sites-enabled/fiirefly
sudo nginx -t && sudo systemctl reload nginx

sudo services/fiirefly/manage.sh createsuperuser   # admin login
```

Then, by hand:

1. Cloudflare dashboard: add the tunnel route (see [DNS](#dns-cloudflare-sillyashcom-zone)).
2. [Arise Connect](https://connect.iiens.net/dashboard/clients): register the redirect
   URI `https://fiirefly-api.sillyash.com/auth/callback/` on the client, put its id and
   secret in `/etc/fiirefly/secret.env` (`sudoedit`), then
   `sudo systemctl restart fiirefly-api`. `deploy.sh` warns while they're empty.

`deploy.sh` refuses to deploy uncommitted changes in `api/`, and it reads git only as
`$SUDO_USER`, so root never touches the repo. It deploys whatever branch is checked
out in `~/Krokodiile`. It never copies `api/.env`: production settings only come
from `/etc/fiirefly`.

## Update

```bash
git -C ~/Krokodiile pull
sudo ~/homelab/services/fiirefly/deploy.sh
```

`manage.sh` runs any other Django command as `www-data` with the service environment
(`sudo ./manage.sh changepassword <user>`, `sudo ./manage.sh shell`, ...).

nginx forwards `X-Forwarded-Proto: https` (Django's `SECURE_PROXY_SSL_HEADER`:
secure cookies and the admin login's CSRF Origin check) and
`X-Forwarded-For: $remote_addr` (already the real client IP via
[`cloudflared-realip.conf`](../nginx/conf.d/cloudflared-realip.conf)).

Back up the DB with
`sudo sqlite3 /var/lib/fiirefly/db.sqlite3 ".backup /path/to/fiirefly-$(date +%F).db"`.
