# Proposal: harden the public SSH endpoint

Status: **proposed, not applied**. See [services/ssh](../services/ssh/README.md) for
the current live config.

## Problem

`sshd` is reachable directly on the public internet (`ssh.sillyash.com:22`, via a
router port-forward — see the [main architecture diagram](../README.md)), running
Debian's stock `openssh-server` config:

- Password authentication is still allowed (no override disabling it).
- No brute-force protection — nothing bans an IP after repeated failed logins.
- Standard port 22, so it gets picked up by every internet-wide SSH scanner within
  minutes of being reachable.

None of this has caused a known incident, but it's the largest gap between "convenient"
and "hardened" on the box today. The preference is to **keep the direct connection**
(no VPN/overlay network) and harden what's there instead.

## Recommended fix

### 1. Key-only authentication

Add a drop-in rather than editing the stock `/etc/ssh/sshd_config`, matching the
override pattern already documented in
[services/ssh/README.md](../services/ssh/README.md):

```bash
# /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
```

**Before enabling this**: confirm a working public key is already installed in
`~/.ssh/authorized_keys` for every account that needs to log in remotely — locking
out password auth without a working key in place means losing remote access entirely
until there's physical/console access to the box.

```bash
sshd -t                      # validate config
systemctl reload ssh
```

### 2. fail2ban for repeat offenders

```bash
apt install fail2ban
```

```ini
# /etc/fail2ban/jail.local
[sshd]
enabled = true
port    = ssh
backend = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
```

```bash
systemctl enable --now fail2ban
fail2ban-client status sshd    # confirm the jail is active
```

This is also a prerequisite for the
[Transmission bot-mitigation proposal](transmission-bot-mitigation.md), which reuses
the same fail2ban install with a second jail.

### 3. Optional, lower priority

- **Move off port 22** to cut down on automated-scanner noise in the logs. Not real
  security (an attacker who specifically targets this host will still find it), but
  meaningfully reduces log spam from opportunistic scanning.
- **`AllowUsers <username>`** in the same drop-in, to restrict which local accounts
  may even attempt an SSH session.

## Verification after applying

- `ssh -o PreferredAuthentications=password <user>@<host>` should be refused.
- `ssh <user>@<host>` with the existing key should still work.
- `fail2ban-client status sshd` shows the jail enabled; deliberately failing auth a
  few times from a test IP should show up as banned in
  `fail2ban-client status sshd`.
