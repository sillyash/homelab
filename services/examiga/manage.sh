#!/usr/bin/env bash
# Run a Django management command against the deployed EX-AMIGA app, as the service
# user and with the service's environment.
#
#   sudo ./manage.sh createsuperuser
#   sudo ./manage.sh changepassword <user>
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0 $*" >&2; exit 1; }
cd /opt/examiga-api
# shellcheck disable=SC2046  # values have no spaces (secret is token_urlsafe)
exec sudo -u www-data env $(grep -hv '^\s*#' /etc/examiga/config.env /etc/examiga/secret.env) \
    .venv/bin/python manage.py "$@"
