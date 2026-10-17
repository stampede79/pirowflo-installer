#!/usr/bin/env bash
set -euo pipefail

PIROWFLO_REPO="https://github.com/stampede79/pirowflo.git"
API_REPO="https://github.com/stampede79/pirowflo-control-api.git"

PIROWFLO_DIR="/opt/pirowflo"
API_DIR="/opt/pirowflo-control-api"

ENV_FILE="/etc/pirowflo-control.env"

INSTALL_USER="${SUDO_USER:-${USER}}"
INSTALL_GROUP="$(id -gn "$INSTALL_USER")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo
    echo "==> $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    fail "Please run this installer with sudo."
fi

command -v git >/dev/null || fail "git is not installed"
command -v python3 >/dev/null || fail "python3 is not installed"

log "Installing system dependencies"

apt-get update
apt-get install -y \
    git \
    python3 \
    python3-venv \
    python3-dev \
    build-essential \
    pkg-config \
    libdbus-1-dev \
    libglib2.0-dev \
    libcairo2-dev \
    gir1.2-glib-2.0 \
    libgirepository-1.0-1 \
    libgirepository-2.0-dev \
    libusb-1.0-0-dev \
    libbluetooth-dev \
    libffi-dev \
    bluetooth \
    bluez \
    bluez-firmware \
    rfkill

log "Installing ANT+ USB permissions"

install -m 0644 \
    "$SCRIPT_DIR/udev/99-antusb.rules" \
    /etc/udev/rules.d/99-antusb.rules

udevadm control --reload-rules
udevadm trigger --subsystem-match=usb

log "Enabling Bluetooth"

rfkill unblock bluetooth
systemctl enable bluetooth.service
systemctl start bluetooth.service

if rfkill list bluetooth | grep -q 'Soft blocked: yes'; then
    fail "Bluetooth is still soft-blocked"
fi

log "Checking installation directories"

if [[ -e "$PIROWFLO_DIR" ]]; then
    fail "$PIROWFLO_DIR already exists"
fi

if [[ -e "$API_DIR" ]]; then
    fail "$API_DIR already exists"
fi

log "Cloning PiRowFlo"

git clone "$PIROWFLO_REPO" "$PIROWFLO_DIR"
chown -R "$INSTALL_USER:$INSTALL_GROUP" "$PIROWFLO_DIR"

log "Creating PiRowFlo virtual environment"

sudo -u "$INSTALL_USER" python3 -m venv "$PIROWFLO_DIR/venv"
sudo -u "$INSTALL_USER" \
    "$PIROWFLO_DIR/venv/bin/pip" install --upgrade pip
sudo -u "$INSTALL_USER" \
    "$PIROWFLO_DIR/venv/bin/pip" install \
    -r "$PIROWFLO_DIR/requirements.txt"

log "Generating PiRowFlo configuration"

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

log "Cloning Control API"

git clone "$API_REPO" "$API_DIR"
chown -R "$INSTALL_USER:$INSTALL_GROUP" "$API_DIR"

log "Creating Control API virtual environment"

sudo -u "$INSTALL_USER" python3 -m venv "$API_DIR/venv"
sudo -u "$INSTALL_USER" \
    "$API_DIR/venv/bin/pip" install --upgrade pip
sudo -u "$INSTALL_USER" \
    "$API_DIR/venv/bin/pip" install \
    -r "$API_DIR/requirements.txt"

log "Configuring Control API"

if [[ ! -f "$ENV_FILE" ]]; then
    API_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"

    cat > "$ENV_FILE" <<EOF
PIROWFLO_API_KEY=$API_KEY
PIROWFLO_SUPERVISORCTL=$PIROWFLO_DIR/venv/bin/supervisorctl
PIROWFLO_SUPERVISOR_CONFIG=$PIROWFLO_DIR/services/supervisord.conf
PIROWFLO_CONTROL_SOCKET=/tmp/pirowflo-control.sock
EOF
    chmod 600 "$ENV_FILE"

    echo
    echo "Generated a new Control API key."
    echo "It has been stored in:"
    echo "  $ENV_FILE"
    echo
    echo "To display it later:"
    echo "  sudo grep '^PIROWFLO_API_KEY=' $ENV_FILE"
    echo
    echo "Configure this key in the PiRowFlo Control App."

else
    log "Keeping existing $ENV_FILE"
fi

log "Installing systemd units"

sed \
    -e "s|#PIROWFLO_DIR#|$PIROWFLO_DIR|g" \
    "$SCRIPT_DIR/systemd/supervisord.service" \
    > /etc/systemd/system/supervisord.service

sed \
    -e "s|#USER#|$INSTALL_USER|g" \
    -e "s|#API_DIR#|$API_DIR|g" \
    "$SCRIPT_DIR/systemd/pirowflo-control.service" \
    > /etc/systemd/system/pirowflo-control.service

systemd-analyze verify \
    /etc/systemd/system/supervisord.service \
    /etc/systemd/system/pirowflo-control.service

log "Enabling services"

systemctl daemon-reload
systemctl enable supervisord.service
systemctl enable pirowflo-control.service

echo
read -r -p \
    "Configure Bluetooth adapters now? [Y/n]: " \
    CONFIGURE_BLUETOOTH

CONFIGURE_BLUETOOTH="${CONFIGURE_BLUETOOTH:-Y}"

if [[ "$CONFIGURE_BLUETOOTH" =~ ^[Yy]$ ]]; then
    "$SCRIPT_DIR/configure-bluetooth.sh" || true
else
    echo
    echo "Bluetooth configuration skipped."
    echo "Configure it later with:"
    echo "  sudo $SCRIPT_DIR/configure-bluetooth.sh"
fi

log "Starting services"

systemctl start supervisord.service
systemctl start pirowflo-control.service

sleep 3

log "Service status"

systemctl --no-pager --full status \
    supervisord.service \
    pirowflo-control.service || true

echo
echo "PiRowFlo installation completed."
echo
echo "PiRowFlo:    $PIROWFLO_DIR"
echo "Control API: $API_DIR"
echo "API port:    8090"
