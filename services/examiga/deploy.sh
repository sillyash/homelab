#!/usr/bin/env bash
# Deploy the EX-AMIGA API from your own checkout to a root-owned /opt/examiga-api.
#
# Usage (pull first, as yourself — root never touches the git repo):
#   git -C ~/examiga-web pull
#   sudo ./deploy.sh           # deploy + restart
#   sudo ./deploy.sh --seed    # also rerun seed.py (replaces the tour dates)
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SRC="${SRC:-/home/${SUDO_USER:-}/examiga-web}"
APP_DIR="/opt/examiga-api"
SERVICE_USER="www-data"
DB_PATH="/var/lib/examiga/examiga.db"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="$SCRIPT_DIR/../systemd/examiga-api.service"
# ─────────────────────────────────────────────────────────────────────────────

info() { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
ok()   { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
die()  { printf '\e[1;31m[ERR ]\e[0m  %s\n' "$*" >&2; exit 1; }

SEED=0
case "${1:-}" in
    "")     ;;
    --seed) SEED=1 ;;
    *)      die "Unknown argument: $1 (usage: sudo ./deploy.sh [--seed])" ;;
esac

[[ $EUID -eq 0 ]] || die "Run as root: sudo ./deploy.sh"
[[ -n "${SUDO_USER:-}" ]] || die "Run through sudo from your own user (git runs as \$SUDO_USER)"
[[ -f "$SRC/api/app.py" ]] || die "No checkout at $SRC (clone sillyash/examiga-web there, or set SRC)"

# ── 1. Source revision (read as the repo owner, never as root) ────────────────
as_owner() { sudo -u "$SUDO_USER" git -C "$SRC" "$@"; }
[[ -z "$(as_owner status --porcelain -- api)" ]] \
    || die "$SRC/api has uncommitted changes — commit or stash them first"
REV="$(as_owner rev-parse --short HEAD)"
info "Deploying $REV from $SRC..."

# ── 2. Application files ──────────────────────────────────────────────────────
# Excluded paths are left alone on the target, so the venv and Python survive.
mkdir -p "$APP_DIR"
rsync -a --delete \
    --exclude='.venv' --exclude='.uv' --exclude='__pycache__' --exclude='*.db' \
    "$SRC/api/" "$APP_DIR/"
echo "$REV" > "$APP_DIR/REVISION"

# ── 3. Python dependencies ────────────────────────────────────────────────────
# The API needs Python >= 3.12 (Debian 12 has 3.11), so uv fetches its own. It goes
# under $APP_DIR because root's default (/root/.local/share/uv) isn't readable by
# the service user.
info "Syncing Python dependencies..."
(cd "$APP_DIR" && UV_PYTHON_INSTALL_DIR="$APP_DIR/.uv/python" uv sync --frozen --no-dev)
chown -R root:root "$APP_DIR"

# ── 4. systemd service ────────────────────────────────────────────────────────
install -m 644 "$UNIT" /etc/systemd/system/examiga-api.service
systemctl daemon-reload
systemctl enable -q examiga-api
systemctl restart examiga-api

# ── 5. Seed (optional) ────────────────────────────────────────────────────────
if [[ $SEED -eq 1 ]]; then
    info "Seeding $DB_PATH..."
    (cd "$APP_DIR" && sudo -u "$SERVICE_USER" env EXAMIGA_DB_PATH="$DB_PATH" .venv/bin/python seed.py)
fi

# ── 6. Smoke test ─────────────────────────────────────────────────────────────
for _ in {1..10}; do
    curl -fsS -o /dev/null http://127.0.0.1:5000/api/tour-dates && break
    sleep 1
done || true
curl -fsS -o /dev/null http://127.0.0.1:5000/api/tour-dates \
    || die "API not answering — check: journalctl -u examiga-api -n 50"

ok "Deployed $REV — https://api.examigaband.com"
