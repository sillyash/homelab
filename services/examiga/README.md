# EX-AMIGA

Band website for EX-AMIGA ([sillyash/examiga-web](https://github.com/sillyash/examiga-web)).
The frontend is on GitHub Pages at `examigaband.com` (deployed by the repo's Actions
workflow). Only the Flask API runs here, at `api.examigaband.com`.

## DNS (Cloudflare, `examigaband.com` zone)

All records are **DNS only** (grey cloud). GitHub can't issue its cert behind the proxy.

| Type | Name | Content |
|---|---|---|
| A | `@` | `185.199.108.153`, `.109.153`, `.110.153`, `.111.153` (4 records) |
| CNAME | `www` | `sillyash.github.io` |
| CNAME | `api` | `jelly.sillyash.com` (ddclient keeps that one current) |
| TXT | `_github-pages-challenge-sillyash` | value from GitHub → Settings → Pages |

## Deploy

From a homelab checkout on the Pi:

```bash
sudo git clone https://github.com/sillyash/examiga-web.git /opt/examiga-web
sudo chown -R www-data: /opt/examiga-web
# API needs Python >= 3.12 (Debian 12 has 3.11), so uv fetches its own. Keep uv's
# files under /opt since www-data can't write to its home.
(cd /opt/examiga-web/api && sudo -u www-data env \
  UV_CACHE_DIR=/opt/examiga-web/.uv/cache UV_PYTHON_INSTALL_DIR=/opt/examiga-web/.uv/python \
  uv sync)   # creates .venv with gunicorn

sudo cp services/systemd/examiga-api.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now examiga-api

sudo certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d api.examigaband.com
sudo cp services/nginx/sites-available/examiga /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/examiga /etc/nginx/sites-enabled/examiga
sudo nginx -t && sudo systemctl reload nginx
```

The SQLite DB (`api/examiga.db`) lives next to the code and persists across restarts.
To update, run `git pull` (plus the `uv sync` above if dependencies changed), then
`sudo systemctl restart examiga-api`.
