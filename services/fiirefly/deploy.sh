#!/usr/bin/env bash
# Deploy the FiiReFLY API (Django: public API + admin) from your own checkout of
# sillyash/Krokodiile to a root-owned /opt/fiirefly-api.
#
# Usage (pull first, as yourself — root never touches the git repo):
#   git -C ~/Krokodiile pull
#   sudo ./deploy.sh           # deploy, migrate, collectstatic, restart
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SRC="${SRC:-/home/${SUDO_USER:-}/Krokodiile}"
APP_DIR="/opt/fiirefly-api"
ETC_DIR="/etc/fiirefly"
STATE_DIR="/var/lib/fiirefly"
HOST="fiirefly-api.sillyash.com"
PORT=5001
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="$SCRIPT_DIR/../systemd/fiirefly-api.service"
# ─────────────────────────────────────────────────────────────────────────────

info() { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
warn() { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
ok()   { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
die()  { printf '\e[1;31m[ERR ]\e[0m  %s\n' "$*" >&2; exit 1; }

[[ $# -eq 0 ]] || die "Unknown argument: $1 (usage: sudo ./deploy.sh)"
[[ $EUID -eq 0 ]] || die "Run as root: sudo ./deploy.sh"
[[ -n "${SUDO_USER:-}" ]] || die "Run through sudo from your own user (git runs as \$SUDO_USER)"
[[ -f "$SRC/api/manage.py" ]] || die "No Django checkout at $SRC (clone sillyash/Krokodiile there, or set SRC)"

# ── 1. Source revision (read as the repo owner, never as root) ────────────────
as_owner() { sudo -u "$SUDO_USER" git -C "$SRC" "$@"; }
[[ -z "$(as_owner status --porcelain -- api)" ]] \
    || die "$SRC/api has uncommitted changes — commit or stash them first"
REV="$(as_owner rev-parse --short HEAD)"
info "Deploying $REV ($(as_owner rev-parse --abbrev-ref HEAD)) from $SRC..."

# ── 2. Application files ──────────────────────────────────────────────────────
# Excluded paths are left alone on the target, so the venv and Python survive.
# .env is excluded too: production settings come from $ETC_DIR, never a dev file.
mkdir -p "$APP_DIR"
rsync -a --delete \
    --exclude='.venv' --exclude='.uv' --exclude='__pycache__' --exclude='.env' \
    --exclude='*.db' --exclude='*.sqlite3' --exclude='staticfiles' \
    "$SRC/api/" "$APP_DIR/"
echo "$REV" > "$APP_DIR/REVISION"

# ── 3. Python dependencies ────────────────────────────────────────────────────
# If uv has to fetch a Python, keep it under $APP_DIR: root's default
# (/root/.local/share/uv) isn't readable by the service user.
info "Syncing Python dependencies..."
(cd "$APP_DIR" && UV_PYTHON_INSTALL_DIR="$APP_DIR/.uv/python" uv sync --frozen --no-dev)
chown -R root:root "$APP_DIR"

# ── 4. Environment ────────────────────────────────────────────────────────────
install -d -m 755 "$ETC_DIR"
install -m 644 "$SCRIPT_DIR/config.env" "$ETC_DIR/config.env"
if [[ ! -f "$ETC_DIR/secret.env" ]]; then
    info "Generating $ETC_DIR/secret.env (first deploy)..."
    (umask 077 && {
        printf 'FIIREFLY_SECRET_KEY=%s\n' \
            "$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
        printf '# Arise Connect client, see https://connect.iiens.net/dashboard/clients\n'
        printf 'FIIREFLY_ARISE_CLIENT_ID=\nFIIREFLY_ARISE_CLIENT_SECRET=\n'
    } > "$ETC_DIR/secret.env")
fi
chown root:root "$ETC_DIR/secret.env"
chmod 600 "$ETC_DIR/secret.env"
for var in FIIREFLY_ARISE_CLIENT_ID FIIREFLY_ARISE_CLIENT_SECRET; do
    grep -Eq "^$var=.+" "$ETC_DIR/secret.env" \
        || warn "$var is empty — Arise login won't work. Fill it: sudoedit $ETC_DIR/secret.env"
done
# StateDirectory only exists once the unit has run; make sure it's there for migrate.
install -d -m 750 -o www-data -g www-data "$STATE_DIR"

# ── 5. Database + static files ────────────────────────────────────────────────
info "Migrating..."
"$SCRIPT_DIR/manage.sh" migrate --noinput
info "Collecting static files..."
"$SCRIPT_DIR/manage.sh" collectstatic --noinput -v 0
chmod 640 "$STATE_DIR/db.sqlite3"

# ── 6. systemd service ────────────────────────────────────────────────────────
install -m 644 "$UNIT" /etc/systemd/system/fiirefly-api.service
systemctl daemon-reload
systemctl enable -q fiirefly-api
systemctl restart fiirefly-api

# ── 7. Smoke test ─────────────────────────────────────────────────────────────
# Pretend to be nginx: Django rejects unknown hosts.
smoke() {
    curl -fsS --max-redirs 0 \
        -H "Host: $HOST" -H 'X-Forwarded-Proto: https' \
        "http://127.0.0.1:$PORT/api/soirees/" | grep -q '"results"'
}
for _ in {1..10}; do smoke && break; sleep 1; done || true
smoke || die "API not answering — check: journalctl -u fiirefly-api -n 50"

ok "Deployed $REV — https://$HOST/api/, admin at https://$HOST/admin/"
