# Monitoring Stack

## Overview

Docker Compose-based monitoring stack for home monitoring with 3 services:
- **Prometheus** (port 9090): metrics collection from multiple targets (homeassistant, cloud, AI services)
- **Grafana** (port 3000): admin password configurable via .env file
- **Uptime Kuma** (port 3001): uptime monitoring with UTC timezone

## Parameterized Configuration

All critical parameters are configurable via `.env` file:
- **PUID/PGID**: User IDs for container execution (customizable via install.sh)
- **BASE_DIR**: Base directory for monitoring stack (customizable via install.sh)
- **DNS_SERVERS**: DNS server addresses (customizable via install.sh, default: 1.1.1.1)
- **GRAFANA_PASSWORD**: Grafana admin password (customizable via install.sh, default: admin)

**Security:** The `.env` file is configured with restricted permissions (600), readable only by the system_user to protect sensitive information like passwords.

## Installation

Run `install.sh` as root to set up:
  1. Creates `.env` with selected system user's UID/GID, BASE_DIR, DNS_SERVERS, and GRAFANA_PASSWORD
  2. Sets .env file permissions to 600 (readable only by system_user) and ownership to system_user
  3. Creates `monitoring.service` systemd unit and sets ownership to system_user
  4. Enables and starts systemd service for auto-start
  5. Password confirmation with double-entry validation ensures accuracy

**Prerequisites:**
- Run as root (sudo ./install.sh)
- Script collects user input for all parameters
- Creates required directories with proper permissions

**Next steps after installation:**
- Enable systemd service: `sudo systemctl enable monitoring.service`
- Start systemd service: `sudo systemctl start monitoring.service`
- View logs: `docker compose logs -f`

## Configuration Files

- **Prometheus config**: `prometheus/etc/prometheus/prometheus.yml`
  - Scrapes targets: homeassistant.home:8123, cloud.home:9292, ai.home:9100
  - Additional AI targets: port 5000 and 8082
  - Configured scrape intervals: 60s (general targets), 30s (AI targets)

## Volume Mappings

All services bind mount `${BASE_DIR}` directory (configurable via .env):
- `prometheus/etc/prometheus/` => container `/etc/prometheus`
- `prometheus/prometheus/` => container `/prometheus`
- `grafana/var/lib/grafana/` => container `/var/lib/grafana`
- `grafana/etc/grafana/` => container `/etc/grafana`
- `uptimekuma/data/` => container `/app/data`
