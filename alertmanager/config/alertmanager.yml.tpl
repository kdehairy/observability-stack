global:
  resolve_timeout: 5m

route:
  receiver: ntfy
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    # Grafana-originated alerts get their own grouping and ntfy topic
    - matchers:
        - grafana_folder != ""
      receiver: ntfy-grafana
      group_by: ['alertname', 'grafana_folder']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h

receivers:
  # title/message/priority come from ntfy-template.yml, rendered via ntfy's
  # inline templating mode. See ntfy-template.yml for details.
  - name: ntfy
    webhook_configs:
      - url: 'https://ntfy.sh/kdehairy_uptime_alert?${NTFY_QUERY}'
        send_resolved: true

  - name: ntfy-grafana
    webhook_configs:
      - url: 'https://ntfy.sh/kdehairy_home_monitors?${NTFY_QUERY}'
        send_resolved: true
