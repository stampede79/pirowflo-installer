#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/pirowflo.env"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    fail "Please run this script with sudo."
fi

command -v bluetoothctl >/dev/null \
    || fail "bluetoothctl is not installed."

mapfile -t CONTROLLERS < <(
    bluetoothctl list |
    awk '/^Controller / {print $2}'
)

echo
echo "Available Bluetooth controllers:"
echo

if [[ ${#CONTROLLERS[@]} -eq 0 ]]; then
    echo "No Bluetooth controllers detected."
    echo
    echo "Connect the Bluetooth adapters and run:"
    echo "  sudo ./configure-bluetooth.sh"
    echo
    exit 2
fi

if [[ ${#CONTROLLERS[@]} -lt 2 ]]; then
    echo "Only one Bluetooth controller was detected."
    echo
    echo "PiRowFlo requires two controllers for this setup:"
    echo "  - one for SmartRow"
    echo "  - one for FTMS"
    echo
    echo "Connect the second Bluetooth adapter and run:"
    echo "  sudo ./configure-bluetooth.sh"
    echo
    exit 2
fi

for i in "${!CONTROLLERS[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${CONTROLLERS[$i]}"
done

echo

select_controller() {
    local description="$1"
    local selection

    while true; do
        read -r -p \
            "Select the controller for $description [1-${#CONTROLLERS[@]}]: " \
            selection

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= ${#CONTROLLERS[@]} )); then
            echo "${CONTROLLERS[$((selection - 1))]}"
            return
        fi

        echo "Invalid selection."
    done
}

SMARTROW_MAC="$(select_controller "SmartRow")"

while true; do
    FTMS_MAC="$(select_controller "FTMS")"

    if [[ "$SMARTROW_MAC" != "$FTMS_MAC" ]]; then
        break
    fi

    echo "SmartRow and FTMS must use different Bluetooth controllers."
    echo
done

cat > "$ENV_FILE" <<EOF
PIROWFLO_SMARTROW_ADAPTER_MAC=$SMARTROW_MAC
PIROWFLO_FTMS_ADAPTER_MAC=$FTMS_MAC
EOF

chmod 644 "$ENV_FILE"

echo
echo "Bluetooth configuration written to:"
echo "  $ENV_FILE"
echo
echo "SmartRow: $SMARTROW_MAC"
echo "FTMS:     $FTMS_MAC"

if systemctl is-active --quiet supervisord.service; then
    echo
    echo "Restarting PiRowFlo..."
    systemctl restart supervisord.service
fi

echo
echo "Bluetooth configuration completed."
