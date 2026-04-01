#!/usr/bin/env bash
# setup-monitoring.sh — install Prometheus + Grafana with Crossplane dashboards
#
# Installs the kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
# and adds a pre-built Crossplane dashboard to Grafana.
#
# Usage:
#   ./setup-monitoring.sh              # interactive
#   ./setup-monitoring.sh --uninstall  # remove the monitoring stack

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

MONITORING_NAMESPACE="monitoring"
GRAFANA_PORT="3000"
PROMETHEUS_PORT="9090"
UNINSTALL=false
[[ "${1:-}" == "--uninstall" ]] && UNINSTALL=true

# ── Banner ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}  Crossplane Local — Monitoring Stack${RESET}\n"

# ── Preflight ──────────────────────────────────────────────────────────────────
if ! kubectl cluster-info &>/dev/null 2>&1; then
  log_error "No Kubernetes cluster reachable. Run ./setup.sh first."
  exit 1
fi

# ── Uninstall path ─────────────────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
  log_section "Removing Monitoring Stack"
  helm uninstall kube-prometheus-stack -n "$MONITORING_NAMESPACE" 2>/dev/null \
    && log_ok "kube-prometheus-stack removed." || log_warn "Not found — skipping."
  kubectl delete namespace "$MONITORING_NAMESPACE" --ignore-not-found
  log_ok "Monitoring stack removed."

  # Kill any lingering port-forwards
  pkill -f "port-forward.*${GRAFANA_PORT}" 2>/dev/null || true
  pkill -f "port-forward.*${PROMETHEUS_PORT}" 2>/dev/null || true
  exit 0
fi

# ── Install ────────────────────────────────────────────────────────────────────
log_section "Step 1 — Helm Repo"
if ! helm repo list 2>/dev/null | grep -q "prometheus-community"; then
  log_info "Adding prometheus-community Helm repo ..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  log_ok "Repo added."
else
  log_ok "prometheus-community repo already present."
fi

log_section "Step 2 — Installing kube-prometheus-stack"
kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if helm status kube-prometheus-stack -n "$MONITORING_NAMESPACE" &>/dev/null 2>&1; then
  log_warn "kube-prometheus-stack already installed — skipping."
else
  log_info "Installing kube-prometheus-stack (this may take ~2 min) ..."
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "$MONITORING_NAMESPACE" \
    --set grafana.adminPassword=crossplane-local \
    --set grafana.defaultDashboardsEnabled=true \
    --set prometheus.prometheusSpec.scrapeInterval=30s \
    --set prometheus.prometheusSpec.retention=7d \
    --set alertmanager.enabled=false \
    --set nodeExporter.enabled=true \
    --wait --timeout 5m
  log_ok "kube-prometheus-stack installed."
fi

# ── Crossplane dashboard ───────────────────────────────────────────────────────
log_section "Step 3 — Crossplane Grafana Dashboard"
log_info "Applying Crossplane metrics dashboard ConfigMap ..."

kubectl apply -f - <<'DASHBOARD'
apiVersion: v1
kind: ConfigMap
metadata:
  name: crossplane-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  crossplane-dashboard.json: |
    {
      "title": "Crossplane Overview",
      "uid": "crossplane-local",
      "tags": ["crossplane"],
      "timezone": "browser",
      "schemaVersion": 38,
      "panels": [
        {
          "id": 1,
          "title": "Managed Resources — Total",
          "type": "stat",
          "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
          "targets": [{
            "expr": "count(crossplane_managed_resource_ready)",
            "legendFormat": "Total"
          }],
          "options": {"colorMode": "background"}
        },
        {
          "id": 2,
          "title": "Managed Resources — Ready",
          "type": "stat",
          "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
          "targets": [{
            "expr": "count(crossplane_managed_resource_ready == 1)",
            "legendFormat": "Ready"
          }],
          "options": {"colorMode": "background", "reduceOptions": {"calcs": ["lastNotNull"]}}
        },
        {
          "id": 3,
          "title": "Managed Resources — Not Ready",
          "type": "stat",
          "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
          "targets": [{
            "expr": "count(crossplane_managed_resource_ready == 0) or vector(0)",
            "legendFormat": "Not Ready"
          }],
          "options": {"colorMode": "background"}
        },
        {
          "id": 4,
          "title": "Reconcile Errors (5m rate)",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
          "targets": [{
            "expr": "rate(crossplane_managed_resource_reconcile_errors_total[5m])",
            "legendFormat": "{{managed_resource_kind}}"
          }]
        },
        {
          "id": 5,
          "title": "Reconcile Duration (p99)",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
          "targets": [{
            "expr": "histogram_quantile(0.99, rate(crossplane_managed_resource_reconcile_duration_seconds_bucket[5m]))",
            "legendFormat": "p99 {{managed_resource_kind}}"
          }]
        },
        {
          "id": 6,
          "title": "Provider Health",
          "type": "table",
          "gridPos": {"h": 6, "w": 24, "x": 0, "y": 12},
          "targets": [{
            "expr": "crossplane_pkg_provider_healthy",
            "legendFormat": "{{name}}",
            "instant": true
          }]
        }
      ],
      "time": {"from": "now-1h", "to": "now"},
      "refresh": "30s"
    }
DASHBOARD

log_ok "Crossplane dashboard ConfigMap applied."

# ── Scrape config for Crossplane metrics ──────────────────────────────────────
log_section "Step 4 — Crossplane ServiceMonitor"
kubectl apply -f - <<'SM'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: crossplane
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - crossplane-system
  selector:
    matchLabels:
      app: crossplane
  endpoints:
    - port: metrics
      interval: 30s
SM

log_ok "ServiceMonitor for Crossplane applied."

# ── Port-forwards ──────────────────────────────────────────────────────────────
log_section "Step 5 — Starting Port-Forwards"

_start_portforward() {
  local svc="$1" ns="$2" local_port="$3" remote_port="$4" pid_file="$5"
  pkill -f "port-forward.*${local_port}" 2>/dev/null || true
  kubectl port-forward -n "$ns" "svc/${svc}" "${local_port}:${remote_port}" &>/dev/null &
  echo $! > "$pid_file"
  sleep 1
  log_ok "${svc} port-forward: http://localhost:${local_port}"
}

_start_portforward "kube-prometheus-stack-grafana"    "$MONITORING_NAMESPACE" "$GRAFANA_PORT"    "80"   "/tmp/grafana-portforward.pid"
_start_portforward "kube-prometheus-stack-prometheus" "$MONITORING_NAMESPACE" "$PROMETHEUS_PORT" "9090" "/tmp/prometheus-portforward.pid"

# ── Done ───────────────────────────────────────────────────────────────────────
log_section "Monitoring Stack Ready"
echo -e "  ${BOLD}Grafana:${RESET}     ${CYAN}http://localhost:${GRAFANA_PORT}${RESET}"
echo -e "             User: ${BOLD}admin${RESET}  |  Password: ${BOLD}crossplane-local${RESET}"
echo -e "  ${BOLD}Prometheus:${RESET}  ${CYAN}http://localhost:${PROMETHEUS_PORT}${RESET}"
echo ""
echo -e "  ${YELLOW}Crossplane dashboard:${RESET}"
echo -e "    Grafana → Dashboards → Crossplane Overview"
echo ""
echo -e "  Stop port-forwards:"
echo -e "    ${CYAN}kill \$(cat /tmp/grafana-portforward.pid) \$(cat /tmp/prometheus-portforward.pid)${RESET}"
echo ""
echo -e "  Uninstall:"
echo -e "    ${CYAN}./setup-monitoring.sh --uninstall${RESET}"
echo ""
