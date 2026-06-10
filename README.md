# Monitoring Stack

## Overview

Docker Compose-based monitoring stack for home monitoring with 5 services:
- **Prometheus** (port 9090): metrics collection from multiple targets (homeassistant, cloud, AI services)
- **Grafana** (port 3000): admin password configurable (default: heroHERO)
- **Uptime Kuma** (port 3001): uptime monitoring with UTC timezone
- **Blackbox Exporter** (port 9115): HTTP and ICMP probes
- **Alertmanager** (port 9093): alert routing and notifications

## Parameterized Configuration

All critical parameters are configured via Makefile prompts:
- **PUID/PGID**: User IDs for container execution (asked during installation)
- **BASE_DIR**: Base directory for monitoring stack (asked during installation)
- **DATA_DIR**: Directory for persistent volumes (asked during installation)
- **DNS_SERVERS**: DNS server address (default: `1.1.1.1`)
- **GRAFANA_PASSWORD**: Grafana admin password (default: heroHERO, confirmed with double-entry)
- **Service ports**: Prometheus (9090), Grafana (3000), Blackbox Exporter (9115), Alertmanager (9093)

**Important**: Configuration is written to `/etc/monitoring/monitoring.conf` (created by `make config`) with permissions 600 — readable only by the system user to protect sensitive information.

## Installation

Run `sudo make install` as root to set up the monitoring stack:
1. Prompts for: system username, DATA_DIR, DNS_SERVERS, GRAFANA_PASSWORD (with confirmation), and all service ports
2. Creates `/etc/monitoring/monitoring.conf` with permissions 600 and ownership ${SYSTEM_UID}:${SYSTEM_GID}
3. Creates `monitoring.service` systemd unit
4. Creates Prometheus rules directory, Grafana configs, Alertmanager configs, and data directories with correct ownership
5. Does **not** enable or start the service automatically

**Prerequisites:**
- Run as root (`sudo make install`)
- Script collects all user input for parameters
- Creates required directories with proper permissions

**Next steps after installation:**
- Enable systemd service: `sudo systemctl enable monitoring.service`
- Start systemd service: `sudo systemctl start monitoring.service`
- View logs: `docker compose logs -f` (from BASE_DIR)

## Configuration Files

### Prometheus (`prometheus/etc/prometheus/prometheus.yml`)
- Scrapes: homeassistant.home:8123 (`/api/prometheus`), cloud.home:9292 (`/metrics`), ai.home:9100, ai.home:5000, model.cloud.home (`/metrics`)
- Intervals: 60s (general), 30s (AI targets and blackbox probes)
- Routes alerts to alertmanager:9093
- Reads rules from `/etc/prometheus/rules/*.yml`

### Alertmanager (`alertmanager/config/alertmanager.yml`)
- Routes alerts via `ntfy.sh` webhooks:
  - `kdehairy_uptime_alert` for general alerts
  - `kdehairy_home_monitors` for Grafana-originated alerts
- Alert grouping: 30s wait, 5m interval, 4h repeat
- Sends resolved alerts

### Blackbox Exporter (`blackbox-exporter/config/blackbox.yml`)
- HTTP probes for: homeassistant.home:8123, darwish.cloud.home/health, music.home/api/v1/ping
- ICMP probes for: 192.168.50.1

### Nginx Reverse Proxy (on host, not in Docker)
**Important**: Uptime Kuma is exposed via Nginx at `http://uptime.cloud.home` (port 80), not directly via Docker port 3001.
- Uptime Kuma config: `nginx/sites-available/uptime-kuma.conf`
- WebSocket support enabled with proper headers
- Must symlink configs to `/etc/nginx/sites-enabled/` on host for nginx to load them

## Volume Mappings

All services bind mount `${BASE_DIR}` directory:
- `prometheus/etc/prometheus/` → container `/etc/prometheus`
- `prometheus/prometheus/` → container `/prometheus` (TSDB)
- `grafana/var/lib/grafana/` → container `/var/lib/grafana`
- `grafana/etc/grafana/` → container `/etc/grafana`
- `blackbox-exporter/config/` → container `/config`
- `alertmanager/config/` → container `/etc/alertmanager`
- `alertmanager/` (data dir) → container `/alertmanager`
- `uptimekuma/data/` → container `/app/data`

## Network Configuration

Services resolve via `.local` and `.cloud.home` FQDNs on the `monitoring_network` Docker network:
- `homeassistant.home:8123` (Prometheus, Home Assistant)
- `cloud.home:9292` (Telegraf)
- `ai.home:9100` (Node exporter)
- `ai.home:5000` (AMD GPU exporter)
- `ai.home:8082` (llama.cpp)
- `uptime.cloud.home` (Uptime Kuma via Nginx)
- `grafana.cloud.home` (via Nginx)
- `prometheus.cloud.home` (via Nginx)
- `192.168.50.0/24` LAN for ICMP probes (Blackbox Exporter)

## Firewall

Host firewall managed by `nftables.conf`:
- Default input policy: **drop**
- LAN (`192.168.50.0/24`): SSH (22), HTTP (80), internal ports (8181, 9292)
- HTTPS (443): open to all
- Docker bridge forwarding explicitly permitted
- Apply firewall rules: `sudo nft -f nftables.conf`

## Quick Commands

```bash
# From BASE_DIR (same directory as compose.yaml, monitoring.service, Makefile)
docker compose --env-file /etc/monitoring/monitoring.conf up --detach   # Start services
docker compose logs -f                                                    # View logs
docker compose down                                                      # Stop services

# Via systemd (preferred for auto-start)
sudo systemctl enable monitoring.service    # Enable at boot (after first install)
sudo systemctl start monitoring.service    # Start now
sudo systemctl status monitoring.service   # Check status
sudo journalctl -u monitoring.service -f  # Follow logs
```

## Service Management

Control via systemd unit file or Makefile:
- **Config**: `sudo make config` - creates `/etc/monitoring/monitoring.conf` (600 permissions)
- **Service file**: `sudo make service` - renders and installs systemd unit
- **Firewall**: `sudo nft -f nftables.conf` - applies firewall rules (requires network interface input)