#!/usr/bin/env bash
# Run a Django management command against the deployed FiiReFLY API, as the service
# user and with the service's environment.
#
#   sudo ./manage.sh createsuperuser
#   sudo ./manage.sh changepassword <user>
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0 $*" >&2; exit 1; }
cd /opt/fiirefly-api
# shellcheck disable=SC2046  # values have no spaces (see config.env)
exec sudo -u www-data env $(grep -hv '^\s*#' /etc/fiirefly/config.env /etc/fiirefly/secret.env) \
    .venv/bin/python manage.py "$@"
