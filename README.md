# Monitoring Stack

## Overview

Docker Compose-based monitoring stack for home monitoring with 2 services, plus standalone Prometheus, Grafana, Fluent Bit, and Loki containers managed outside of Compose:
- **Prometheus** (port 9090): metrics collection from multiple targets (homeassistant, cloud, AI services). Runs as its own systemd unit (`prometheus.service`), not part of `compose.yaml`
- **Grafana** (port 3000): admin password configurable (default: heroHERO). Runs as its own systemd unit (`grafana.service`), not part of `compose.yaml`
- **Blackbox Exporter** (port 9115): HTTP and ICMP probes
- **Alertmanager** (port 9093): alert routing and notifications
- **Fluent Bit** (host port 514, internal 5140): receives syslog and forwards to Loki. Runs as its own systemd unit (`fluent-bit.service`), not part of `compose.yaml`
- **Loki** (port 3100): log aggregation and storage. Runs as its own systemd unit (`loki.service`), not part of `compose.yaml`

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
3. Creates the external `monitoring_network` Docker network (shared by the Compose stack and the standalone Prometheus/Grafana/Fluent Bit/Loki containers)
4. Creates `monitoring.service`, `prometheus.service`, `grafana.service`, `fluent-bit.service`, and `loki.service` systemd units
5. Creates Prometheus rules directory, Grafana configs, Alertmanager configs, and data directories with correct ownership
6. Does **not** enable or start any service automatically

**Prerequisites:**
- Run as root (`sudo make install`)
- Script collects all user input for parameters
- Creates required directories with proper permissions

**Next steps after installation:**
- Start everything: `sudo make start-all` (or `sudo systemctl enable --now monitoring.service prometheus.service grafana.service fluent-bit.service loki.service` for boot-persistent enablement)
- View logs: `docker compose logs -f` (from BASE_DIR) for the Compose stack, `journalctl -u prometheus.service -f` / `journalctl -u grafana.service -f` / `journalctl -u fluent-bit.service -f` / `journalctl -u loki.service -f` for the standalone containers

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
All Nginx site configs must be symlinked to `/etc/nginx/sites-enabled/` on the host for nginx to load them
- Sites with `listen 443 ssl` (`homeassistant.conf`, `openwebui.conf`) share SSL/HTTP2 settings via `nginx/snippets/ssl-params.conf`, which must also be symlinked to `/etc/nginx/snippets/ssl-params.conf` on the host

## Volume Mappings

All services bind mount `${BASE_DIR}` directory:
- `prometheus/etc/prometheus/` → container `/etc/prometheus` (standalone container, started via `prometheus.service`, not Compose)
- `prometheus/prometheus/` → container `/prometheus` (TSDB)
- `grafana/var/lib/grafana/` → container `/var/lib/grafana` (standalone container, started via `grafana.service`, not Compose)
- `grafana/etc/grafana/` → container `/etc/grafana`
- `blackbox-exporter/config/` → container `/config`
- `alertmanager/config/` → container `/etc/alertmanager`
- `alertmanager/` (data dir) → container `/alertmanager`
- `fluent-bit/etc/fluent-bit/` → container `/etc/fluent-bit` (standalone container, started via `fluent-bit.service`, not Compose)
- `fluent-bit/` (data dir) → container `/var/log/fluent-bit`
- `loki/etc/loki/` → container `/etc/loki` (standalone container, started via `loki.service`, not Compose)
- `loki/chunks` (data dir) → container `/etc/loki/chunks`
- `loki/rules` (data dir) → container `/etc/loki/rules`

## Network Configuration

`monitoring_network` is an externally-managed Docker network (created by `sudo make network`/`install`, not owned by Compose) so the standalone Prometheus/Grafana/Fluent Bit/Loki containers and the Compose-managed services can resolve each other by container name (Prometheus and Loki need to reach `alertmanager`; Prometheus also reaches `blackbox-exporter`; Grafana and Fluent Bit need to reach `loki`).

Services resolve via `.local` and `.cloud.home` FQDNs on the `monitoring_network` Docker network:
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
# From BASE_DIR (same directory as compose.yaml, monitoring.service, Makefile)
docker compose --env-file /etc/monitoring/monitoring.conf up --detach   # Start services
docker compose logs -f                                                    # View logs
docker compose down                                                      # Stop services

# Via systemd (preferred for auto-start)
sudo systemctl enable monitoring.service    # Enable at boot (after first install)
sudo systemctl start monitoring.service    # Start now
sudo systemctl status monitoring.service   # Check status
sudo journalctl -u monitoring.service -f  # Follow logs

# Prometheus, Grafana, Fluent Bit, and Loki run standalone, outside the Compose stack
sudo systemctl enable prometheus.service grafana.service fluent-bit.service loki.service
sudo systemctl start prometheus.service grafana.service fluent-bit.service loki.service
sudo systemctl status prometheus.service
sudo journalctl -u prometheus.service -f

# Or use the Makefile wrappers to start/stop everything at once
sudo make start-all
sudo make stop-all
```

## Service Management

Control via systemd unit files or Makefile:
- **Config**: `sudo make config` - creates `/etc/monitoring/monitoring.conf` (600 permissions)
- **Network**: `sudo make network` - creates the external `monitoring_network` Docker network
- **Service file**: `sudo make service` - renders and installs `monitoring.service`, `prometheus.service`, `grafana.service`, `fluent-bit.service`, and `loki.service`
- **Firewall**: `sudo nft -f nftables.conf` - applies firewall rules (requires network interface input)
- **Start/stop everything**: `sudo make start-all` / `sudo make stop-all`
- Operations: use `systemctl`/`journalctl` directly on individual units (no per-unit Makefile wrappers)