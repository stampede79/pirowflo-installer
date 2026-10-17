# PiRowFlo Installer

Installer for a Raspberry Pi based PiRowFlo setup with SmartRow, Bluetooth FTMS,
ANT+ and the PiRowFlo Control API.

## Components

The installer deploys:

- PiRowFlo
  https://github.com/stampede79/pirowflo
- PiRowFlo Control API
  https://github.com/stampede79/pirowflo-control-api

The Flutter Control App is maintained separately and is not installed on the
Raspberry Pi.

## Installation

Clone the installer:

```bash
git clone https://github.com/stampede79/pirowflo-installer.git
cd pirowflo-installer
sudo ./install.sh
```

The installer:

1. installs the required system packages
2. installs PiRowFlo to `/opt/pirowflo`
3. creates the PiRowFlo Python virtual environment
4. generates the local PiRowFlo configuration
5. installs the Control API to `/opt/pirowflo-control-api`
6. creates the Control API Python virtual environment
7. generates an API key
8. installs and enables the systemd services
9. optionally configures the Bluetooth adapters

## Bluetooth configuration

The Bluetooth adapters do not have to be connected during the initial
installation.

The installer can configure them immediately if they are available.

To configure or change the Bluetooth adapters later, run:

```bash
cd ~/pirowflo-installer
sudo ./configure-bluetooth.sh
```

The script lists all available Bluetooth controllers and asks which controller
should be used for:

- SmartRow
- FTMS advertising

SmartRow and FTMS must use different Bluetooth controllers.

The selected adapter configuration is stored in:

```text
/etc/pirowflo.env
```

## Control API

The Control API listens on TCP port `8090`.

The API key and API configuration are stored in:

```text
/etc/pirowflo-control.env
```

To display the generated API key:

```bash
sudo grep '^PIROWFLO_API_KEY=' /etc/pirowflo-control.env
```

The API key is required by the PiRowFlo Control App.

## Updating

Update PiRowFlo and the Control API from GitHub:

```bash
cd ~/pirowflo-installer
sudo ./update.sh
```

The updater:

1. checks both repositories for local changes
2. stops PiRowFlo and the Control API
3. updates both repositories using fast-forward-only Git pulls
4. updates Python dependencies
5. regenerates the local PiRowFlo configuration
6. restarts the services

If an update fails after the services have been stopped, the updater attempts to
start the existing services again.

Local changes in `/opt/pirowflo` or `/opt/pirowflo-control-api` cause the update
to abort instead of overwriting them.

## Services

Check the PiRowFlo Supervisor service:

```bash
systemctl status supervisord.service
```

Check the Control API:

```bash
systemctl status pirowflo-control.service
```

Check the individual PiRowFlo processes:

```bash
/opt/pirowflo/venv/bin/supervisorctl \
  -c /opt/pirowflo/services/supervisord.conf \
  status
```

## Installation paths

PiRowFlo:

```text
/opt/pirowflo
```

Control API:

```text
/opt/pirowflo-control-api
```

Bluetooth configuration:

```text
/etc/pirowflo.env
```

Control API configuration:

```text
/etc/pirowflo-control.env
```
