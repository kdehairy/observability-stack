# Monitoring Stack

## Overview

Home monitoring stack. Every service runs as a standalone Docker container managed by its own systemd unit — there is no Docker Compose involved:
- **Prometheus** (port 9090): metrics collection from multiple targets (homeassistant, cloud, AI services). `prometheus.service`
- **Grafana** (port 3000): admin password configurable (default: heroHERO). `grafana.service`
- **Blackbox Exporter** (port 9115): HTTP and ICMP probes. `blackbox-exporter.service`
- **Alertmanager** (port 9093): alert routing and notifications. `alertmanager.service`
- **Fluent Bit** (host port 514, internal 5140): receives syslog and forwards to Loki. `fluent-bit.service`
- **Loki** (port 3100): log aggregation and storage. `loki.service`

## Parameterized Configuration

All critical parameters are configured via Makefile prompts:
- **PUID/PGID**: User IDs for container execution (asked during installation)
- **BASE_DIR**: Base directory for monitoring stack (asked during installation)
- **DATA_DIR**: Directory for persistent volumes (asked during installation)
- **DNS_SERVERS**: DNS server address (default: `1.1.1.1`)
- **GRAFANA_PASSWORD**: Grafana admin password (default: heroHERO, confirmed with double-entry)
- **Service ports**: Prometheus (9090), Grafana (3000), Blackbox Exporter (9115), Alertmanager (9093), Loki (3100), Fluent Bit (514)

**Important**: Configuration is written to `/etc/monitoring/monitoring.conf` (created by `make config`) with permissions 600 — readable only by the system user to protect sensitive information.

## Installation

Run `sudo make install` as root to set up the monitoring stack:
1. Prompts for: system username, DATA_DIR, DNS_SERVERS, GRAFANA_PASSWORD (with confirmation), and all service ports
2. Creates `/etc/monitoring/monitoring.conf` with permissions 600 and ownership ${SYSTEM_UID}:${SYSTEM_GID}
3. Creates the external `monitoring_network` Docker network shared by all six standalone containers
4. Creates `prometheus.service`, `grafana.service`, `fluent-bit.service`, `loki.service`, `alertmanager.service`, and `blackbox-exporter.service` systemd units
5. Creates Prometheus rules directory, Grafana configs, Alertmanager configs, and data directories with correct ownership
6. Does **not** enable or start any service automatically

**Prerequisites:**
- Run as root (`sudo make install`)
- Script collects all user input for parameters
- Creates required directories with proper permissions

**Next steps after installation:**
- Start everything: `sudo make start-all` (or `sudo systemctl enable --now <unit>...` per unit for boot-persistent enablement)
- View logs: `sudo journalctl -u <unit>.service -f` per container

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
- Within each topic, the `severity` label picks the ntfy priority: `critical` → urgent, `warning` → high, `info` → low, anything else → ntfy's default
- Alert grouping: 30s wait, 5m interval, 4h repeat
- Sends resolved alerts

### Blackbox Exporter (`blackbox-exporter/config/blackbox.yml`)
- HTTP probes for: homeassistant.home:8123, darwish.cloud.home/health, music.home/api/v1/ping
- ICMP probes for: 192.168.50.1

### Nginx Reverse Proxy (on host, not in Docker)
All Nginx site configs must be symlinked to `/etc/nginx/sites-enabled/` on the host for nginx to load them
- Sites with `listen 443 ssl` (`homeassistant.conf`, `openwebui.conf`) share SSL/HTTP2 settings via `nginx/snippets/ssl-params.conf`, which must also be symlinked to `/etc/nginx/snippets/ssl-params.conf` on the host

## Volume Mappings

All services bind mount `${BASE_DIR}`/`${DATA_DIR}` directories directly into their `docker run` invocation (no Compose volumes):
- `prometheus/etc/prometheus/` → container `/etc/prometheus`
- `prometheus/prometheus/` → container `/prometheus` (TSDB)
- `grafana/var/lib/grafana/` → container `/var/lib/grafana`
- `grafana/etc/grafana/` → container `/etc/grafana`
- `blackbox-exporter/config/` → container `/config`
- `alertmanager/config/` → container `/etc/alertmanager`
- `alertmanager/` (data dir) → container `/alertmanager`
- `fluent-bit/etc/fluent-bit/` → container `/etc/fluent-bit`
- `fluent-bit/` (data dir) → container `/var/log/fluent-bit`
- `loki/etc/loki/` → container `/etc/loki`
- `loki/chunks` (data dir) → container `/etc/loki/chunks`
- `loki/rules` (data dir) → container `/etc/loki/rules`

## Network Configuration

`monitoring_network` is an externally-managed Docker network (created by `sudo make network`/`install`), shared by all six standalone containers so they can resolve each other by container name: Prometheus and Loki reach `alertmanager`; Prometheus reaches `blackbox-exporter`; Grafana and Fluent Bit reach `loki`.

Services also resolve via `.local` and `.cloud.home` FQDNs on the host's DNS:
- `homeassistant.home:8123` (Prometheus, Home Assistant)
- `cloud.home:9292` (Telegraf)
- `ai.home:9100` (Node exporter)
- `ai.home:5000` (AMD GPU exporter)
- `ai.home:8082` (llama.cpp)
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
# Start/stop everything at once
sudo make start-all
sudo make stop-all

# Per-unit systemd control
sudo systemctl enable --now prometheus.service
sudo systemctl status prometheus.service
sudo journalctl -u prometheus.service -f
```

## Service Management

Control via systemd unit files or Makefile:
- **Config**: `sudo make config` - creates `/etc/monitoring/monitoring.conf` (600 permissions)
- **Network**: `sudo make network` - creates the external `monitoring_network` Docker network
- **Service file**: `sudo make service` - renders and installs all six systemd units
- **Firewall**: `sudo nft -f nftables.conf` - applies firewall rules (requires network interface input)
- **Start/stop everything**: `sudo make start-all` / `sudo make stop-all`
- **Per-service install/uninstall**: `make install-<name>` / `make uninstall-<name>` for `prometheus`, `grafana`, `fluent-bit`, `loki`, `alertmanager`, `blackbox-exporter`
- Operations: use `systemctl`/`journalctl` directly on individual units
