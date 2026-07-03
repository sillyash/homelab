# Jellyfin

Media server, reachable at `https://jelly.sillyash.com` via the
[nginx](../nginx/README.md) reverse proxy (nginx handles TLS; Jellyfin itself listens
on plain HTTP on `8096`, bound to localhost only from the outside world's perspective).

## Install

Installed from the [official Jellyfin apt repo](https://jellyfin.org/docs/general/installation/linux/)
(`apt install jellyfin`), which also pulls in `jellyfin-web` and `jellyfin-ffmpeg`.

## Layout

Stock paths from `/etc/default/jellyfin`, unmodified:

| Path | Purpose |
|---|---|
| `/etc/jellyfin` | config |
| `/var/lib/jellyfin` | data (metadata, plugins, library DB) |
| `/var/log/jellyfin` | logs |
| `/var/cache/jellyfin` | cache/transcoding |

## systemd

Stock unit (`/lib/systemd/system/jellyfin.service`), runs as the dedicated
`jellyfin` user/group. No overrides in `jellyfin.service.d/` — the drop-in that ships
with the package is left fully commented out.

```bash
systemctl enable --now jellyfin
```
