# FiiReFLY bot

Discord idle-game bot for the FiiReFLY list ([Gibaslayer/FiiReFLY](https://github.com/Gibaslayer/FiiReFLY),
discord.py + aiosqlite). The same process also serves a read-only leaderboard API
(aiohttp, `GET /leaderboard?limit=10`) for the frontend at `https://fiirefly.iiens.net`,
published at `fiirefly-bot.sillyash.com`: one systemd service, one tunnel-only nginx vhost.

Not to be confused with the [FiiReFLY API](../fiirefly/README.md) (the site's Django
backend, `fiirefly-api`): different repo, different service, different DB.

## DNS (Cloudflare, `sillyash.com` zone)

`fiirefly-bot` is a [Cloudflare Tunnel](../cloudflared/README.md) route, created from
the tunnel's Public Hostnames tab, service `https://127.0.0.1:8443`, Origin Server Name
`fiirefly-bot.sillyash.com`, no Cloudflare Access (public read-only data). nginx rate
limits it (`fiirefly_bot_api`, 10 req/s, burst 20): every request is a SQLite query.

The Discord side needs nothing inbound: the bot connects out to Discord's gateway.

## Layout

Same split as [fiirefly](../fiirefly/README.md): you own the git checkout, root owns
the deployed copy, the service can only write its state directory.

| Path | Owner | What |
|---|---|---|
| `~/FiiReFLY-bot` | you | git checkout, on the `deploy-jazz` branch (uv packaging: `pyproject.toml` + `uv.lock`) |
| `/opt/fiirefly-bot` | root | deployed copy + `.venv` + uv's Python 3.12 in `.uv/` (`REVISION` = commit) |
| `/etc/fiirefly-bot/config.env` | root | `SITE_ORIGIN`, `API_PORT`, copied from [`config.env`](config.env) on each deploy |
| `/etc/fiirefly-bot/secret.env` | root, 600 | `DISCORD_TOKEN`, filled by hand, never overwritten |
| `/var/lib/fiirefly-bot/firefly.db` | www-data | SQLite DB (systemd `StateDirectory`, also the working directory) |
| `/var/lib/fiirefly-bot/discord.log` | www-data | discord.py log (DEBUG), truncated on restart, rotated at 20M by [`logrotate`](logrotate) |

The bot opens `firefly.db` and `discord.log` relative to its working directory, so the
[unit](../systemd/fiirefly-bot.service) runs it from `/var/lib/fiirefly-bot` and the
code needs no change. `print()` output (e.g. "… is ready to use with N commands") goes
to the journal.

The API listens on port 5002 (8080, the bot's default, is dropservice's). The bot
binds it on `0.0.0.0` (hard-coded in `main.py`), so it's also reachable on the LAN at
`<pi>:5002`. The router doesn't forward it, and the data is public anyway.

## Deploy

First install, from a homelab checkout on the Pi:

```bash
git clone git@github.com:Gibaslayer/FiiReFLY.git ~/FiiReFLY-bot
git -C ~/FiiReFLY-bot switch deploy-jazz
sudo services/fiirefly-bot/deploy.sh   # rsync, uv sync, env files, unit, logrotate

sudoedit /etc/fiirefly-bot/secret.env  # DISCORD_TOKEN=...
sudo systemctl restart fiirefly-bot

sudo certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d fiirefly-bot.sillyash.com
sudo cp services/nginx/conf.d/rate-limit.conf /etc/nginx/conf.d/
sudo cp services/nginx/sites-available/fiirefly-bot /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/fiirefly-bot /etc/nginx/sites-enabled/fiirefly-bot
sudo nginx -t && sudo systemctl reload nginx
```

Then add the tunnel route in the Cloudflare dashboard (see [DNS](#dns-cloudflare-sillyashcom-zone)).

While `DISCORD_TOKEN` is empty, `deploy.sh` installs and enables the unit but doesn't
start it (the bot would crash-loop). Once the token is set, it restarts the bot and
waits for `GET /leaderboard` to answer. `deploy.sh` refuses a dirty checkout, reads
git only as `$SUDO_USER`, deploys whatever branch is checked out, and never copies a
`.env` or a local `firefly.db`.

## Update

```bash
git -C ~/FiiReFLY-bot pull
sudo ~/homelab/services/fiirefly-bot/deploy.sh
```

## Checks

```bash
systemctl status fiirefly-bot
journalctl -u fiirefly-bot -n 50
curl -s 'http://127.0.0.1:5002/leaderboard?limit=3'
curl -sI https://fiirefly-bot.sillyash.com/leaderboard   # Access-Control-Allow-Origin: https://fiirefly.iiens.net
```

Back up the DB with
`sudo sqlite3 /var/lib/fiirefly-bot/firefly.db ".backup /path/to/fiirefly-bot-$(date +%F).db"`.
