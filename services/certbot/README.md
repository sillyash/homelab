# certbot

Issues and renews Let's Encrypt certificates using the **Cloudflare DNS-01
challenge** (`python3-certbot-dns-cloudflare` plugin) instead of the HTTP-01
challenge. DNS-01 is used because the box is on a residential connection behind a
dynamic IP ([ddclient](../ddclient/README.md) keeps DNS pointed at it) — proving
domain ownership via a DNS TXT record is simpler and more reliable than depending on
inbound port 80 always reaching this exact machine.

## Architecture

```mermaid
graph LR
    timer["certbot.timer<br>twice daily"]
    certbot["certbot<br>+ dns-cloudflare plugin"]
    cf["Cloudflare API"]
    txt["_acme-challenge<br>TXT record"]
    le["Let's Encrypt"]
    nginx["nginx"]

    timer -->|triggers| certbot
    certbot -->|creates| txt
    txt --> cf
    certbot -->|requests validation| le
    le -->|checks TXT via DNS| cf
    le -->|issues cert| certbot
    certbot -->|writes to /etc/letsencrypt/live| nginx
```

## Install

```bash
apt install certbot python3-certbot-dns-cloudflare
```

## Credentials

Certbot's Cloudflare plugin reads an API token from a credentials file (never
committed — see [`cloudflare.ini.example`](cloudflare.ini.example)):

```bash
install -m 600 /dev/null /etc/letsencrypt/cloudflare.ini
# then fill in dns_cloudflare_api_token = <token>
```

The token needs only **Zone → DNS → Edit**, scoped to the `sillyash.com` zone.

## Issuing a cert

```bash
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d sub.sillyash.com \
  --non-interactive --agree-tos --email admin@sillyash.com
```

## Renewal

Handled automatically by the `certbot.timer` systemd timer that ships with the
package — runs twice daily (`00:00` / `12:00`, with randomized delay), calling
`certbot renew` which only actually renews certs within 30 days of expiry.

```bash
systemctl status certbot.timer
```

## Current certificates

- `drop.sillyash.com` — used by [dropservice](../dropservice/README.md)
- `jelly.sillyash.com` (covers `jelly.sillyash.com` + `transmission.sillyash.com` as
  SANs) — used by [Jellyfin](../jellyfin/README.md) and
  [Transmission](../transmission/README.md)
