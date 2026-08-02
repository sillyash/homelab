# NZBGet

Usenet downloader — wired into [Sonarr](../sonarr/README.md)/
[Radarr](../radarr/README.md) as a download client, connected to
**Eweka** (`sslreader.eweka.nl:563`, SSL, 20 connections — plan caps at 50, kept
below that intentionally) as the Usenet provider, with **NZBgeek** as the indexer
searched through [Prowlarr](../prowlarr/README.md). Not exposed publicly — no
nginx vhost, bound to `127.0.0.1` only; only Sonarr/Radarr on the same box talk to
it.

## Architecture

```mermaid
graph LR
    prowlarr["Prowlarr<br>NZBgeek indexer"] --> sonarr["Sonarr"]
    prowlarr --> radarr["Radarr"]
    sonarr -->|grab| nzbget["NZBGet :6789<br>127.0.0.1 only"]
    radarr -->|grab| nzbget
    nzbget -->|NNTP/SSL| eweka["Eweka<br>news provider"]
    nzbget -->|Category1| movies["/media/sillyash/Movies/_incoming"]
    nzbget -->|Category2| series["/media/sillyash/Series/_incoming"]
```

## Install

```bash
apt install nzbget
```

Debian's package ships **no active systemd unit** — only a commented-out example at
`/usr/share/doc/nzbget/examples/nzbget.systemd`, running as generic `daemon:daemon`.
A dedicated `nzbget` user and a real unit were created instead, matching the pattern
used for the rest of the stack (own user, shared `media` group).

`/etc/systemd/system/nzbget.service` (custom unit):

```ini
[Unit]
Description=NZBGet Daemon
Documentation=http://nzbget.net/Documentation
After=network.target

[Service]
User=nzbget
Group=media
Type=forking
ExecStart=/usr/bin/nzbget -D
ExecStop=/usr/bin/nzbget -Q
ExecReload=/usr/bin/nzbget -O
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## Config

`/etc/nzbget.conf` (mode `640`, owned by `nzbget:media` — not committed, contains
the control password). Relevant non-secret settings:

| Key | Value | Note |
|---|---|---|
| `MainDir` | `/var/lib/nzbget/downloads` | base download dir |
| `Category1.Name` / `Category1.DestDir` | `Movies` / `/media/sillyash/Movies/_incoming` | matches Radarr's `movieCategory` |
| `Category2.Name` / `Category2.DestDir` | `Series` / `/media/sillyash/Series/_incoming` | matches Sonarr's `tvCategory` |

Same same-filesystem-hardlink reasoning as Transmission's `_incoming` dirs — each
category's `DestDir` is on the same physical disk as the corresponding *arr app's
root folder.

Control port `6789`, bound to `127.0.0.1` only (`ss -tlnp` shows
`127.0.0.1:6789`) — reachable from Sonarr/Radarr on the same box, not from outside.

## Provider

`News-Server` settings (`Server1.*` in `/etc/nzbget.conf`):

| Key | Value |
|---|---|
| `Server1.Name` | `Eweka` |
| `Server1.Host` | `sslreader.eweka.nl` |
| `Server1.Port` | `563` |
| `Server1.Encryption` | `yes` |
| `Server1.Connections` | `20` |

Connection tested via NZBGet's own JSON-RPC `testserver` method (empty result =
success, a descriptive string = the actual failure reason) rather than trusting a
"saved successfully" response, since NZBGet will happily save an unreachable/wrong
server without complaint.

The download client itself is `enable: true` on both Sonarr and Radarr now — grabs
route through NZBGet whenever a result comes from a Usenet indexer (NZBgeek, via
Prowlarr); torrent results still go to
[Transmission](../transmission/README.md) as before, decided by Sonarr/Radarr per
release based on which indexer it came from.

## Useful commands

```bash
sudo systemctl restart nzbget
systemctl status nzbget
journalctl -u nzbget -n 100 --no-pager

# API (JSON-RPC, control user/pass in /root/.arr-api-keys)
curl -s http://$NZBGET_USER:$NZBGET_PASS@localhost:6789/jsonrpc/status
```
