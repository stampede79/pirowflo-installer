#!/usr/bin/env bash
set -euo pipefail

PIROWFLO_DIR="/opt/pirowflo"
API_DIR="/opt/pirowflo-control-api"

log() {
    echo
    echo "==> $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    fail "Please run this updater with sudo."
fi

INSTALL_USER="${SUDO_USER:-${USER}}"
INSTALL_GROUP="$(id -gn "$INSTALL_USER")"

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo
        echo "ERROR: Update failed. Attempting to restart services..."

        systemctl start supervisord.service || true
        systemctl start pirowflo-control.service || true
    fi

    exit "$exit_code"
}

trap cleanup EXIT

check_repo() {
    local repo="$1"

    [[ -d "$repo/.git" ]] \
        || fail "$repo is not a Git repository"

    if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
        fail "$repo contains local changes. Update aborted."
    fi
}

log "Checking repositories"

check_repo "$PIROWFLO_DIR"
check_repo "$API_DIR"

log "Stopping PiRowFlo services"

systemctl stop pirowflo-control.service
systemctl stop supervisord.service

log "Updating PiRowFlo"

sudo -u "$INSTALL_USER" git -C "$PIROWFLO_DIR" pull --ff-only

sudo -u "$INSTALL_USER" \
    "$PIROWFLO_DIR/venv/bin/pip" install \
    -r "$PIROWFLO_DIR/requirements.txt"

log "Regenerating PiRowFlo configuration"

cp \
    "$PIROWFLO_DIR/services/supervisord.conf.orig" \
    "$PIROWFLO_DIR/services/supervisord.conf"

sed -i \
    -e "s|#USER#|$INSTALL_USER|g" \
    -e "s|#PYTHON3#|$PIROWFLO_DIR/venv/bin/python3|g" \
    -e "s|#REPO_DIR#|$PIROWFLO_DIR|g" \
    "$PIROWFLO_DIR/services/supervisord.conf"

cp \
    "$PIROWFLO_DIR/src/logging.conf.orig" \
    "$PIROWFLO_DIR/src/logging.conf"

sed -i \
    "s|#REPO_DIR#|$PIROWFLO_DIR|g" \
    "$PIROWFLO_DIR/src/logging.conf"

chown \
    "$INSTALL_USER:$INSTALL_GROUP" \
    "$PIROWFLO_DIR/services/supervisord.conf" \
    "$PIROWFLO_DIR/src/logging.conf"

log "Updating Control API"

sudo -u "$INSTALL_USER" git -C "$API_DIR" pull --ff-only

sudo -u "$INSTALL_USER" \
    "$API_DIR/venv/bin/pip" install \
    -r "$API_DIR/requirements.txt"

log "Starting services"

systemctl start supervisord.service
systemctl start pirowflo-control.service

sleep 3

log "Service status"

systemctl --no-pager --full status \
    supervisord.service \
    pirowflo-control.service || true

trap - EXIT

echo
echo "PiRowFlo update completed."
