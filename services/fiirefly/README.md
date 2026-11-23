# FiiReFLY

Django REST API for the FiiReFLY site ([sillyash/FiiReFLY](https://github.com/sillyash/FiiReFLY),
`api/`). The frontend is static, on the school's personal pages at
`https://fiirefly.iiens.net` (see [Frontend](#frontend-fiireflyiiensnet)). The API runs
here at `fiirefly-api.sillyash.com`: one Gunicorn service, one tunnel-only nginx vhost.

The hostname is `fiirefly-api`, not `api.fiirefly`: Cloudflare's free Universal SSL
only covers one level of subdomain (`*.sillyash.com`), so a two-level name has no
edge cert when proxied.

The frontend (`iiens.net`) and the API (`sillyash.com`) are different sites, so a
session cookie would be third-party (blocked by Safari, partitioned by Firefox). The
frontend authenticates with a DRF token instead: after the Arise login,
`/auth/callback/` redirects to `https://fiirefly.iiens.net/#/connexion?code=...`, the
frontend trades that 2-minute signed code for a token (`POST /auth/token/`) and sends
`Authorization: Token ...`. Only the Django admin, on the API host, uses the session.

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
| `~/FiiReFLY` | you | git checkout: pull and edit here, never as root |
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
git clone git@github.com:sillyash/FiiReFLY.git ~/FiiReFLY
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
   URI `https://fiirefly-api.sillyash.com/auth/callback/` on the client (it stays on the
   API host, the frontend moving doesn't change it), put its id and
   secret in `/etc/fiirefly/secret.env` (`sudoedit`), then
   `sudo systemctl restart fiirefly-api`. `deploy.sh` warns while they're empty.

`deploy.sh` refuses to deploy uncommitted changes in `api/`, and it reads git only as
`$SUDO_USER`, so root never touches the repo. It deploys whatever branch is checked
out in `~/FiiReFLY`. It never copies `api/.env`: production settings only come
from `/etc/fiirefly`.

## Frontend (fiirefly.iiens.net)

Not on this box: the Vue build is plain static files on the school's personal pages
(Apache, `*.iiens.net` cert, static only), under the association account `fiirefly`.

| What | Value |
|---|---|
| SSH | `fiirefly@perso.iiens.net`, key `~/.ssh/id_ed25519_bazzite` (`~/.ssh/config`: `Host perso.iiens.net`, `IdentityFile`, `IdentitiesOnly yes`) |
| Docroot | `~/html/` (mode `2710`, leave it as is), served at the root of `https://fiirefly.iiens.net` |
| Deploy | `just deploy-web` from the FiiReFLY checkout: `npm run build`, then `rsync -rltz --delete web/dist/ fiirefly@perso.iiens.net:html/` |

The router uses hash URLs, so no rewrite / `.htaccess` is needed. The build needs
Node >= 22; the Pi's Debian `nodejs` is 18, so on the Pi prefix with
`npx -p node@24` (e.g. `npx -p node@24 just deploy-web`) or build elsewhere.

The API side only needs `FIIREFLY_FRONTEND_URL` (where the login lands) and
`FIIREFLY_CORS_ALLOWED_ORIGINS` in [`config.env`](config.env) to point at it.

The old `fiirefly.sillyash.com` (GitHub Pages) is gone: CNAME deleted from the zone,
Pages disabled on the repo.

## Update

```bash
git -C ~/FiiReFLY pull
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
