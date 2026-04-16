#!/bin/bash

# Monitoring Stack Installer
# This script sets up the monitoring stack with configurable parameters
# Must be run as root (sudo ./install.sh)

set -e

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Please run with sudo: sudo ./install.sh"
    exit 1
fi

# Get script directory as BASE_DIR
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="${SCRIPT_DIR}"

# Ask for system user
echo "Enter the system username to use for monitoring services:"
read -r SYSTEM_USER

# Ask for DNS server(s) (comma-separated, default: 1.1.1.1)
echo "Enter DNS server(s) for monitoring services (comma-separated, default: 1.1.1.1):"
read -r DNS_SERVERS
if [ -z "$DNS_SERVERS" ]; then
    DNS_SERVERS="1.1.1.1"
fi

# Ask for Grafana admin password (default: admin)
echo "Enter Grafana admin password (default: admin):"
read -sr GRAFANA_PASSWORD
echo ""

# Ask to confirm password
echo "Retype Grafana admin password:"
read -sr GRAFANA_PASSWORD_CONFIRM
echo ""

# Validate passwords match
if [ "$GRAFANA_PASSWORD" != "$GRAFANA_PASSWORD_CONFIRM" ]; then
    echo "Error: Passwords do not match. Please run the script again."
    exit 1
fi

if [ -z "$GRAFANA_PASSWORD" ]; then
    GRAFANA_PASSWORD="admin"
fi

# Check if user exists, create if not
if ! id -u "$SYSTEM_USER" &>/dev/null; then
    echo "User $SYSTEM_USER does not exist. Creating it..."
    useradd -s /sbin/nologin "$SYSTEM_USER"
fi
SYSTEM_UID=$(id -u "$SYSTEM_USER")
SYSTEM_GID=$(id -g "$SYSTEM_USER")

# Create .env file
cat > "${BASE_DIR}/.env" << EOF
PUID=${SYSTEM_UID}
PGID=${SYSTEM_GID}
BASE_DIR=${BASE_DIR}
DNS_SERVERS=${DNS_SERVERS}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
EOF

# Make .env file readable only by the system user
chmod 600 "${BASE_DIR}/.env"
chown "${SYSTEM_UID}:${SYSTEM_GID}" "${BASE_DIR}/.env"

echo ".env file created with:"
echo "  PUID=${SYSTEM_UID}"
echo "  PGID=${SYSTEM_GID}"
echo "  BASE_DIR=${BASE_DIR}"
echo "  DNS_SERVERS=${DNS_SERVERS}"
echo "  GRAFANA_PASSWORD=${GRAFANA_PASSWORD}"
echo "  Permissions: Owner read/write only"
echo "  File ownership: ${SYSTEM_UID}:${SYSTEM_GID}"

# Ensure required directories exist
echo "Creating required directories..."
mkdir -p "${BASE_DIR}/.prometheus/etc/prometheus"
mkdir -p "${BASE_DIR}/.prometheus/prometheus"
mkdir -p "${BASE_DIR}/.grafana/var/lib/grafana"
mkdir -p "${BASE_DIR}/.grafana/etc/grafana"
mkdir -p "${BASE_DIR}/.uptimekuma/data"

# Set permissions and ownership
echo "Setting permissions and ownership..."
chown -R "${SYSTEM_UID}:${SYSTEM_GID}" "${BASE_DIR}/.prometheus"
chown -R "${SYSTEM_UID}:${SYSTEM_GID}" "${BASE_DIR}/.grafana"
chown -R "${SYSTEM_UID}:${SYSTEM_GID}" "${BASE_DIR}/.uptimekuma/data"

# Create monitoring.service
cat > "${BASE_DIR}/monitoring.service" << EOF
[Unit]
Description=Monitoring services all in one.
Requires=docker.service
After=docker.service

[Service]
Type=simple
WorkingDirectory=${BASE_DIR}
ExecStart=/usr/bin/docker compose --env-file .env up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10s
User=${SYSTEM_USER}
Group=${SYSTEM_USER}

[Install]
WantedBy=multi-user.target
EOF

# Set ownership of monitoring.service file
chown "${SYSTEM_UID}:${SYSTEM_GID}" "${BASE_DIR}/monitoring.service"

echo "monitoring.service created with:"
echo "  WorkingDirectory=${BASE_DIR}"
echo "  User=${SYSTEM_USER}"
echo "  Group=${SYSTEM_USER}"

# Copy systemd unit file to systemd directory and enable it
echo "Setting up systemd service..."
SYSTEMD_DIR="/etc/systemd/system"
mkdir -p "${SYSTEMD_DIR}"
cp "${BASE_DIR}/monitoring.service" "${SYSTEMD_DIR}/monitoring.service"
systemctl daemon-reload

echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Enable systemd service: sudo systemctl enable monitoring.service"
echo "2. Start systemd service: sudo systemctl start monitoring.service"
