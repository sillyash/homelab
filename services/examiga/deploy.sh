#!/usr/bin/env bash
# Deploy the EX-AMIGA API (Django: public API + content admin) from your own checkout
# to a root-owned /opt/examiga-api.
#
# Usage (pull first, as yourself — root never touches the git repo):
#   git -C ~/examiga-web pull
#   sudo ./deploy.sh           # deploy, migrate, collectstatic, restart
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SRC="${SRC:-/home/${SUDO_USER:-}/examiga-web}"
APP_DIR="/opt/examiga-api"
ETC_DIR="/etc/examiga"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="$SCRIPT_DIR/../systemd/examiga-api.service"
# ─────────────────────────────────────────────────────────────────────────────

info() { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
ok()   { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
die()  { printf '\e[1;31m[ERR ]\e[0m  %s\n' "$*" >&2; exit 1; }

[[ $# -eq 0 ]] || die "Unknown argument: $1 (usage: sudo ./deploy.sh)"
[[ $EUID -eq 0 ]] || die "Run as root: sudo ./deploy.sh"
[[ -n "${SUDO_USER:-}" ]] || die "Run through sudo from your own user (git runs as \$SUDO_USER)"
[[ -f "$SRC/api/manage.py" ]] || die "No Django checkout at $SRC (clone sillyash/examiga-web there, or set SRC)"

# ── 1. Source revision (read as the repo owner, never as root) ────────────────
as_owner() { sudo -u "$SUDO_USER" git -C "$SRC" "$@"; }
[[ -z "$(as_owner status --porcelain -- api)" ]] \
    || die "$SRC/api has uncommitted changes — commit or stash them first"
REV="$(as_owner rev-parse --short HEAD)"
info "Deploying $REV ($(as_owner rev-parse --abbrev-ref HEAD)) from $SRC..."

# ── 2. Application files ──────────────────────────────────────────────────────
# Excluded paths are left alone on the target, so the venv and Python survive.
mkdir -p "$APP_DIR"
rsync -a --delete \
    --exclude='.venv' --exclude='.uv' --exclude='__pycache__' \
    --exclude='*.db' --exclude='*.sqlite3' --exclude='staticfiles' \
    "$SRC/api/" "$APP_DIR/"
echo "$REV" > "$APP_DIR/REVISION"

# ── 3. Python dependencies ────────────────────────────────────────────────────
# The API needs Python >= 3.12 (Debian 12 has 3.11), so uv fetches its own. It goes
# under $APP_DIR because root's default (/root/.local/share/uv) isn't readable by
# the service user.
info "Syncing Python dependencies..."
(cd "$APP_DIR" && UV_PYTHON_INSTALL_DIR="$APP_DIR/.uv/python" uv sync --frozen --no-dev)
chown -R root:root "$APP_DIR"

# ── 4. Environment ────────────────────────────────────────────────────────────
install -d -m 755 "$ETC_DIR"
install -m 644 "$SCRIPT_DIR/config.env" "$ETC_DIR/config.env"
if [[ ! -f "$ETC_DIR/secret.env" ]]; then
    info "Generating $ETC_DIR/secret.env (first deploy)..."
    (umask 077 && printf 'EXAMIGA_SECRET_KEY=%s\n' \
        "$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')" > "$ETC_DIR/secret.env")
fi
chown root:root "$ETC_DIR/secret.env"
chmod 600 "$ETC_DIR/secret.env"
# StateDirectory only exists once the unit has run; make sure it's there for migrate.
install -d -m 750 -o www-data -g www-data /var/lib/examiga

# ── 5. Database + static files ────────────────────────────────────────────────
# The first migrate creates the tables and loads api/backup/*.json.
info "Migrating..."
"$SCRIPT_DIR/manage.sh" migrate --noinput
info "Collecting static files..."
"$SCRIPT_DIR/manage.sh" collectstatic --noinput -v 0
chmod 640 /var/lib/examiga/db.sqlite3

# ── 6. systemd service ────────────────────────────────────────────────────────
install -m 644 "$UNIT" /etc/systemd/system/examiga-api.service
systemctl daemon-reload
systemctl enable -q examiga-api
systemctl restart examiga-api

# ── 7. Smoke test ─────────────────────────────────────────────────────────────
# Pretend to be nginx: Django rejects unknown hosts and redirects plain HTTP.
smoke() {
    curl -fsS --max-redirs 0 \
        -H 'Host: api.examigaband.com' -H 'X-Forwarded-Proto: https' \
        http://127.0.0.1:5000/api/shoutouts | grep -q '"results"'
}
for _ in {1..10}; do smoke && break; sleep 1; done || true
smoke || die "API not answering — check: journalctl -u examiga-api -n 50"

ok "Deployed $REV — https://api.examigaband.com, admin at https://admin.examigaband.com/admin/"
