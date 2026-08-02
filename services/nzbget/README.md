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
| `MainDir` | `/media/sillyash/Series/_nzbget-tmp` | base download/staging dir — see note below |
| `Category1.Name` / `Category1.DestDir` | `Movies` / `/media/sillyash/Movies/_incoming` | matches Radarr's `movieCategory` |
| `Category2.Name` / `Category2.DestDir` | `Series` / `/media/sillyash/Series/_incoming` | matches Sonarr's `tvCategory` |

Same same-filesystem-hardlink reasoning as Transmission's `_incoming` dirs — each
category's `DestDir` is on the same physical disk as the corresponding *arr app's
root folder.

**`MainDir` must not be left on the root filesystem.** It originally defaulted to
`/var/lib/nzbget/downloads` (the root SD card, ~29GB total) — active downloads sit
fully assembled/unpacked here (`MainDir/inter`) before being moved to the
category's `DestDir`, and a queue of a few 4K/2160p remux releases (routinely
3–17GB *per episode*) filled the root disk to 100% within a session, which in turn
crashed Jellyfin (it refuses to start with <2GB free anywhere it touches). Moved to
`/media/sillyash/Series/_nzbget-tmp` (447GB free at time of writing) instead — the
Series disk was picked over Movies purely because it had more headroom; there's no
way to set this per-category, so a movie grab does incur one extra cross-disk copy
during NZBGet's own inter→dest move (harmless, just slightly slower than if it
matched). If root ever fills up again, check `df -h /` and `du -xh --max-depth=2
/var` first — `/var/cache/apt` and `/var/log/journal` are the other usual
suspects (`apt clean`, `journalctl --vacuum-size=200M`).

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
