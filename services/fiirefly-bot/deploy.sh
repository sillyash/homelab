#!/usr/bin/env bash
# Deploy the FiiReFLY Discord bot (+ its read-only leaderboard API) from your own
# checkout of Gibaslayer/FiiReFLY to a root-owned /opt/fiirefly-bot.
#
# Usage (pull first, as yourself — root never touches the git repo):
#   git -C ~/FiiReFLY-bot pull
#   sudo ./deploy.sh           # deploy, uv sync, restart, smoke test
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SRC="${SRC:-/home/${SUDO_USER:-}/FiiReFLY-bot}"
APP_DIR="/opt/fiirefly-bot"
ETC_DIR="/etc/fiirefly-bot"
STATE_DIR="/var/lib/fiirefly-bot"
PORT=5002   # must match API_PORT in config.env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="$SCRIPT_DIR/../systemd/fiirefly-bot.service"
# ─────────────────────────────────────────────────────────────────────────────

info() { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
warn() { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
ok()   { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
die()  { printf '\e[1;31m[ERR ]\e[0m  %s\n' "$*" >&2; exit 1; }

[[ $# -eq 0 ]] || die "Unknown argument: $1 (usage: sudo ./deploy.sh)"
[[ $EUID -eq 0 ]] || die "Run as root: sudo ./deploy.sh"
[[ -n "${SUDO_USER:-}" ]] || die "Run through sudo from your own user (git runs as \$SUDO_USER)"
[[ -f "$SRC/main.py" ]] || die "No bot checkout at $SRC (clone Gibaslayer/FiiReFLY there, or set SRC)"
[[ -f "$SRC/uv.lock" ]] || die "No uv.lock in $SRC — check out a branch with uv packaging (deploy-jazz)"

# ── 1. Source revision (read as the repo owner, never as root) ────────────────
as_owner() { sudo -u "$SUDO_USER" git -C "$SRC" "$@"; }
[[ -z "$(as_owner status --porcelain)" ]] \
    || die "$SRC has uncommitted changes — commit or stash them first"
REV="$(as_owner rev-parse --short HEAD)"
info "Deploying $REV ($(as_owner rev-parse --abbrev-ref HEAD)) from $SRC..."

# ── 2. Application files ──────────────────────────────────────────────────────
# Excluded paths are left alone on the target, so the venv and Python survive.
# .env is excluded too: production settings come from $ETC_DIR, never a dev file.
mkdir -p "$APP_DIR"
rsync -a --delete \
    --exclude='.git' --exclude='.venv' --exclude='.uv' --exclude='__pycache__' \
    --exclude='.env' --exclude='*.db' --exclude='discord.log' --exclude='.vscode' \
    "$SRC/" "$APP_DIR/"
echo "$REV" > "$APP_DIR/REVISION"

# ── 3. Python dependencies ────────────────────────────────────────────────────
# The lock wants Python 3.12 (Debian has 3.11): uv fetches it, kept under $APP_DIR
# because root's default (/root/.local/share/uv) isn't readable by the service user.
info "Syncing Python dependencies..."
(cd "$APP_DIR" && UV_PYTHON_INSTALL_DIR="$APP_DIR/.uv/python" uv sync --frozen --no-dev)
chown -R root:root "$APP_DIR"

# ── 4. Environment ────────────────────────────────────────────────────────────
install -d -m 755 "$ETC_DIR"
install -m 644 "$SCRIPT_DIR/config.env" "$ETC_DIR/config.env"
if [[ ! -f "$ETC_DIR/secret.env" ]]; then
    info "Creating $ETC_DIR/secret.env (first deploy)..."
    (umask 077 && {
        printf '# Bot token, see https://discord.com/developers/applications\n'
        printf 'DISCORD_TOKEN=\n'
    } > "$ETC_DIR/secret.env")
fi
chown root:root "$ETC_DIR/secret.env"
chmod 600 "$ETC_DIR/secret.env"
install -d -m 750 -o www-data -g www-data "$STATE_DIR"
install -m 644 "$SCRIPT_DIR/logrotate" /etc/logrotate.d/fiirefly-bot

# ── 5. systemd service ────────────────────────────────────────────────────────
install -m 644 "$UNIT" /etc/systemd/system/fiirefly-bot.service
systemctl daemon-reload
systemctl enable -q fiirefly-bot

if ! grep -Eq '^DISCORD_TOKEN=.+' "$ETC_DIR/secret.env"; then
    systemctl stop fiirefly-bot 2>/dev/null || true
    warn "DISCORD_TOKEN is empty — bot installed but not started."
    warn "Fill it: sudoedit $ETC_DIR/secret.env, then: sudo systemctl restart fiirefly-bot"
    exit 0
fi
systemctl restart fiirefly-bot

# ── 6. Smoke test ─────────────────────────────────────────────────────────────
# The API only comes up after the Discord login (setup_hook): give it some time.
smoke() { curl -fsS "http://127.0.0.1:$PORT/leaderboard?limit=1" | grep -q '^\['; }
for _ in {1..20}; do smoke && break; sleep 1; done || true
smoke || die "Leaderboard API not answering — check: journalctl -u fiirefly-bot -n 50"

ok "Deployed $REV — https://fiirefly-bot.sillyash.com/leaderboard"
