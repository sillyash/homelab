# SSH

Remote shell access to the box, port `22`, reachable directly (not proxied through
nginx — nginx only terminates HTTP/HTTPS, and SSH is a raw TCP protocol). The
`ssh.sillyash.com` DNS record kept up to date by [ddclient](../ddclient/README.md)
just points at the box's public IP; reaching it depends on the home router
forwarding port 22 to this machine.

## Architecture

```mermaid
graph LR
    Internet -->|router port-forward| sshd["sshd"]
    sshd --> shell["local shell access"]
```

## Config

Stock Debian `openssh-server` config — `/etc/ssh/sshd_config` is unmodified from the
package default, and `/etc/ssh/sshd_config.d/` (which the main config `Include`s) has
no local override files. Notable stock settings currently in effect:

```
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
```

No local hardening (e.g. disabling password auth, changing the port, `AllowUsers`)
has been layered on yet — worth revisiting if this box stays internet-facing.
