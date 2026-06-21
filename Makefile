SHELL        := /bin/bash
.ONESHELL:

PREFIX                  ?=
CONF_DEST               := $(PREFIX)/etc/monitoring/monitoring.conf
SERVICE_SRC             := monitoring.service
SERVICE_DEST            := $(PREFIX)/etc/systemd/system/monitoring.service
PROMETHEUS_SERVICE_SRC  := prometheus.service
PROMETHEUS_SERVICE_DEST := $(PREFIX)/etc/systemd/system/prometheus.service
NFTABLES_SRC            := nftables.conf
NFTABLES_DEST           := $(PREFIX)/etc/nftables.conf
BASE_DIR                := $(shell pwd)
NETWORK_NAME            := monitoring_network

.PHONY: help config service install install-prometheus uninstall uninstall-prometheus firewall network

help:
	@echo "Usage: sudo make <target>"
	echo ""
	echo "Setup:"
	echo "  config   Prompt for parameters, write $(CONF_DEST), create data dirs"
	echo "  network  Create the external monitoring_network Docker network"
	echo "  service  Render and install the monitoring.service and prometheus.service unit files from $(CONF_DEST)"
	echo "  install    Run network then service"
	echo "  install-prometheus  Run network then install just the prometheus.service unit"
	echo "  uninstall  Disable and remove the systemd units, config file, and network"
	echo "  uninstall-prometheus  Disable and remove just the prometheus.service unit"
	echo "  firewall   Render and apply nftables rules (requires config)"
	echo ""
	echo "Use systemctl/journalctl directly to manage monitoring.service and prometheus.service."

$(CONF_DEST):
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make config)"; exit 1; }

	read -rp "Data directory for persistent volumes [$(BASE_DIR)]: " DATA_DIR
	DATA_DIR=$${DATA_DIR:-$(BASE_DIR)}

	read -rp "System username for monitoring services: " SYSTEM_USER
	if ! id -u "$$SYSTEM_USER" &>/dev/null; then
		read -rp "User '$$SYSTEM_USER' does not exist — create it? [y/N]: " yn
		[[ "$$yn" =~ ^[Yy] ]] || { echo "Aborted."; exit 1; }
		useradd -s /sbin/nologin "$$SYSTEM_USER"
	fi
	SYSTEM_UID=$$(id -u "$$SYSTEM_USER")
	SYSTEM_GID=$$(id -g "$$SYSTEM_USER")

	read -rp "DNS servers, comma-separated [1.1.1.1]: " DNS_SERVERS
	DNS_SERVERS=$${DNS_SERVERS:-1.1.1.1}

	read -rsp "Grafana admin password [admin]: " GRAFANA_PASSWORD; echo
	read -rsp "Retype password: " GRAFANA_PASSWORD_CONFIRM; echo
	[[ "$$GRAFANA_PASSWORD" == "$$GRAFANA_PASSWORD_CONFIRM" ]] || { echo "Error: passwords do not match"; exit 1; }
	GRAFANA_PASSWORD=$${GRAFANA_PASSWORD:-admin}

	read -rp "Prometheus host port [9090]: " PROMETHEUS_PORT
	PROMETHEUS_PORT=$${PROMETHEUS_PORT:-9090}
	read -rp "Grafana host port [3000]: " GRAFANA_PORT
	GRAFANA_PORT=$${GRAFANA_PORT:-3000}
	read -rp "Blackbox Exporter host port [9115]: " BLACKBOX_EXPORTER_PORT
	BLACKBOX_EXPORTER_PORT=$${BLACKBOX_EXPORTER_PORT:-9115}
	read -rp "Loki host port [3100]: " LOKI_PORT
	LOKI_PORT=$${LOKI_PORT:-3100}
	read -rp "Fluent-bit host port [514]: " FLUENT_BIT_PORT
	FLUENT_BIT_PORT=$${FLUENT_BIT_PORT:-514}
	echo "FLUENT_BIT_DATA=$$DATA_DIR"

	mkdir -p "$(PREFIX)/etc/monitoring"
	{
			echo "PUID=$$SYSTEM_UID"
			echo "PGID=$$SYSTEM_GID"
			echo "BASE_DIR=$(BASE_DIR)"
			echo "DATA_DIR=$$DATA_DIR"
			echo "DNS_SERVERS=$$DNS_SERVERS"
			echo "GRAFANA_PASSWORD=$$GRAFANA_PASSWORD"
			echo "PROMETHEUS_PORT=$$PROMETHEUS_PORT"
			echo "GRAFANA_PORT=$$GRAFANA_PORT"
			echo "BLACKBOX_EXPORTER_PORT=$$BLACKBOX_EXPORTER_PORT"
			echo "LOKI_PORT=$$LOKI_PORT"
			echo "FLUENT_BIT_PORT=$$FLUENT_BIT_PORT"
		} > "$(CONF_DEST)"
	chmod 600 "$(CONF_DEST)"
	chown "$$SYSTEM_UID:$$SYSTEM_GID" "$(CONF_DEST)"
	echo "Config written: $(CONF_DEST)"

	mkdir -p "$(BASE_DIR)/prometheus/etc/prometheus/rules"
	mkdir -p "$$DATA_DIR/prometheus"
	mkdir -p "$$DATA_DIR/grafana/var/lib/grafana"
	mkdir -p "$(BASE_DIR)/grafana/etc/grafana"
	mkdir -p "$(BASE_DIR)/grafana/etc/grafana/provisioning/datasources"
	mkdir -p "$(BASE_DIR)/alertmanager/config"
	mkdir -p "$$DATA_DIR/alertmanager"
	mkdir -p "$$DATA_DIR/loki/chunks"
	mkdir -p "$$DATA_DIR/loki/rules"
	mkdir -p "$$DATA_DIR/fluent-bit"
	mkdir -p "$(BASE_DIR)/fluent-bit/etc/fluent-bit"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$(BASE_DIR)/prometheus/etc"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$$DATA_DIR/prometheus"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$(BASE_DIR)/grafana/etc"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$$DATA_DIR/grafana/var"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$(BASE_DIR)/alertmanager/config"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$$DATA_DIR/alertmanager"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$$DATA_DIR/loki"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$$DATA_DIR/fluent-bit"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$(BASE_DIR)/fluent-bit/etc"
	echo "Directories created and ownership set"

config: $(CONF_DEST)

$(NFTABLES_DEST): $(NFTABLES_SRC)
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make firewall)"; exit 1; }
	DETECTED=$$(ip route | awk '/^default/ {print $$5; exit}')
	read -rp "Network interface [$${DETECTED:-none detected}]: " IFACE
	IFACE=$${IFACE:-$$DETECTED}
	[[ -n "$$IFACE" ]] || { echo "Error: no network interface specified"; exit 1; }
	export IFACE
	envsubst '$$IFACE' < "$(BASE_DIR)/$(NFTABLES_SRC)" > "$(NFTABLES_DEST)"
	nft -f "$(NFTABLES_DEST)"
	systemctl enable nftables
	systemctl restart nftables
	echo "Firewall rules applied: $(NFTABLES_DEST)"

firewall: $(NFTABLES_DEST)

network:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make network)"; exit 1; }
	docker network inspect $(NETWORK_NAME) >/dev/null 2>&1 || docker network create $(NETWORK_NAME)
	echo "Docker network '$(NETWORK_NAME)' ready"

$(SERVICE_DEST): $(CONF_DEST) $(SERVICE_SRC)
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make service)"; exit 1; }

	mkdir -p "$(PREFIX)/etc/systemd/system"
	set -a; source "$(CONF_DEST)"; set +a
	export CONF_DEST="$(CONF_DEST)"
	envsubst < "$(BASE_DIR)/$(SERVICE_SRC)" > "$(SERVICE_DEST)"
	chown "$$PUID:$$PGID" "$(SERVICE_DEST)"
	systemctl daemon-reload
	echo "Unit installed: $(SERVICE_DEST)"
	echo "Next: sudo systemctl enable --now monitoring.service"

$(PROMETHEUS_SERVICE_DEST): $(CONF_DEST) $(PROMETHEUS_SERVICE_SRC)
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make service)"; exit 1; }

	mkdir -p "$(PREFIX)/etc/systemd/system"
	set -a; source "$(CONF_DEST)"; set +a
	export CONF_DEST="$(CONF_DEST)"
	envsubst < "$(BASE_DIR)/$(PROMETHEUS_SERVICE_SRC)" > "$(PROMETHEUS_SERVICE_DEST)"
	chown "$$PUID:$$PGID" "$(PROMETHEUS_SERVICE_DEST)"
	systemctl daemon-reload
	echo "Unit installed: $(PROMETHEUS_SERVICE_DEST)"
	echo "Next: sudo systemctl enable --now prometheus.service"

service: $(SERVICE_DEST) $(PROMETHEUS_SERVICE_DEST)

install: network $(SERVICE_DEST) $(PROMETHEUS_SERVICE_DEST)

install-prometheus: network $(PROMETHEUS_SERVICE_DEST)

uninstall:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall)"; exit 1; }
	systemctl disable --now monitoring.service 2>/dev/null || true
	systemctl disable --now prometheus.service 2>/dev/null || true
	rm -f "$(SERVICE_DEST)" "$(PROMETHEUS_SERVICE_DEST)"
	systemctl daemon-reload
	rm -f "$(CONF_DEST)"
	rmdir --ignore-fail-on-non-empty "$(PREFIX)/etc/monitoring" 2>/dev/null || true
	docker network rm $(NETWORK_NAME) 2>/dev/null || true
	echo "Uninstalled"

uninstall-prometheus:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall-prometheus)"; exit 1; }
	systemctl disable --now prometheus.service 2>/dev/null || true
	rm -f "$(PROMETHEUS_SERVICE_DEST)"
	systemctl daemon-reload
	echo "Uninstalled prometheus.service"
