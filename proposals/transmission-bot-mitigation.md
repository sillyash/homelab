# Proposal: mitigate bot traffic against Transmission's public login

Status: **proposed, not applied**. See
[services/transmission](../services/transmission/README.md) for the current live
config.

## Problem

`transmission.sillyash.com` is intentionally public — the RPC/web UI is exposed
through nginx so torrents can be queued remotely from anywhere. That's a deliberate
choice and stays as-is: **no VPN-gating, no client certs, it stays public.**

The actual issue: bots continuously probe the login prompt. `rpc-authentication-required`
is `true`, so nothing gets through today, but the constant probing is unwanted —
it's noise in the logs, wastes CPU/bandwidth on repeated TLS handshakes and auth
checks, and raises the risk that some future rate-limit or lockout behavior ends up
blocking legitimate use along with the bots.

## Recommended fix

Add throttling and auto-banning in front of Transmission, entirely at the nginx/OS
layer — no change to Transmission's own config or the fact that it's public.

### 1. Rate-limit at nginx

In `services/nginx/sites-available/jellyfin` (the vhost file that holds the
`transmission.sillyash.com` server block):

```nginx
# in the http{} context (e.g. /etc/nginx/conf.d/rate-limit.conf)
limit_req_zone $binary_remote_addr zone=transmission_rpc:10m rate=5r/m;

# inside the transmission.sillyash.com server{} block, in location /
limit_req zone=transmission_rpc burst=5 nodelay;
```

`5r/m` (5 requests/minute per IP, burst of 5) is generous for a human occasionally
adding a torrent from the web UI, but throttles a bot hammering the login endpoint.

### 2. fail2ban jail on repeated 401s

Reuses the fail2ban install from the
[SSH hardening proposal](ssh-hardening.md) — add a second jail watching nginx's
access log for repeated unauthorized responses on this vhost:

```ini
# /etc/fail2ban/filter.d/transmission-rpc.conf
[Definition]
failregex = ^<HOST> .* "(GET|POST) /transmission/rpc.*" 401
ignoreregex =
```

```ini
# /etc/fail2ban/jail.local (add alongside the sshd jail)
[transmission-rpc]
enabled  = true
filter   = transmission-rpc
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 8
findtime = 10m
bantime  = 2h
```

```bash
systemctl restart fail2ban
fail2ban-client status transmission-rpc
```

### 3. Optional: cap concurrent connections per IP

Extra defense against connection-flood-style bot behavior, same `nginx` config
location as the rate limit:

```nginx
limit_conn_zone $binary_remote_addr zone=transmission_conn:10m;
limit_conn transmission_conn 5;
```

## Verification after applying

- `nginx -t && systemctl reload nginx` after adding the `limit_req`/`limit_conn`
  config.
- Hammer the login endpoint with more than 5 requests/minute from one IP and confirm
  nginx starts returning `503` before it reaches Transmission.
- `fail2ban-client status transmission-rpc` shows the jail active; confirm repeated
  401s from a test IP result in a ban.
- Normal usage (occasionally logging in and adding a torrent from the web UI) should
  be unaffected.
