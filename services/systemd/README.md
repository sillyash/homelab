# systemd

Holds a copy of `drop.service` — the actual unit deployed on this box for
[dropservice](../dropservice/README.md) (a submodule; full app README, `setup.sh`,
and this same unit definition also live there — kept here too as part of the "what's
actually running" inventory for this repo).

## Useful commands

```bash
sudo systemctl restart drop      # apply a code or .env change (Restart=always means it also auto-restarts on crash)
systemctl status drop            # running?
journalctl -u drop -n 50 --no-pager
journalctl -u drop -f             # follow logs live (e.g. while testing an upload)

# after editing /etc/systemd/system/drop.service itself (not just the app):
sudo systemctl daemon-reload
sudo systemctl restart drop
```
