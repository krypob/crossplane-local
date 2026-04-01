#!/usr/bin/env bash
# setup-gui.sh — optional GUI dashboard for the local Crossplane environment
#
# Available dashboards:
#   1) Headlamp            — modern Kubernetes web UI with Crossplane plugin (open source)
#   2) Kubernetes Dashboard — official Kubernetes web UI (open source, no account required)
#
# Usage:
#   ./setup-gui.sh                  # interactive — choose which GUI to install
#   GUI=headlamp ./setup-gui.sh     # skip prompt
#   GUI=k8sdashboard ./setup-gui.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

# ── Banner ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}  Crossplane Local — GUI Setup${RESET}\n"

# ── Preflight ──────────────────────────────────────────────────────────────────
if ! kubectl cluster-info &>/dev/null 2>&1; then
  log_error "No Kubernetes cluster reachable. Run ./setup.sh first."
  exit 1
fi

# ── GUI selection ──────────────────────────────────────────────────────────────
log_section "Choose a GUI Dashboard"

_select_gui() {
  if [[ -n "${GUI:-}" ]]; then SELECTED_GUI="$GUI"; return; fi

  echo -e "  ${BOLD}1) Headlamp${RESET}  — open-source Kubernetes UI + Crossplane plugin"
  echo -e "     Runs in your browser. Installed locally via Helm."
  echo -e "     Access: http://localhost:4466\n"
  echo -e "  ${BOLD}2) Kubernetes Dashboard${RESET}  — official Kubernetes web UI"
  echo -e "     Open-source. No account required. Installed locally via Helm."
  echo -e "     Access: http://localhost:8443\n"
  echo -e "  ${BOLD}3) Both${RESET}\n"

  while true; do
    read -rp "$(echo -e "${YELLOW}  Choice [1-3]: ${RESET}")" choice
    case "${choice:-}" in
      1|headlamp)      SELECTED_GUI="headlamp";      return ;;
      2|k8sdashboard)  SELECTED_GUI="k8sdashboard";  return ;;
      3|both)          SELECTED_GUI="both";           return ;;
      *) echo "  Please enter 1, 2, or 3." ;;
    esac
  done
}

SELECTED_GUI=""
_select_gui
log_ok "Selected: ${BOLD}${SELECTED_GUI}${RESET}"

# ── Headlamp ───────────────────────────────────────────────────────────────────
_install_headlamp() {
  log_section "Installing Headlamp"

  # Add Helm repo
  if ! helm repo list 2>/dev/null | grep -q "headlamp"; then
    log_info "Adding Headlamp Helm repo ..."
    helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
    helm repo update
  fi

  # Install into headlamp namespace
  if helm status headlamp -n headlamp &>/dev/null 2>&1; then
    log_warn "Headlamp already installed — skipping."
  else
    log_info "Installing Headlamp via Helm ..."
    kubectl create namespace headlamp --dry-run=client -o yaml | kubectl apply -f -
    helm install headlamp headlamp/headlamp \
      --namespace headlamp \
      --set replicaCount=1 \
      --wait --timeout 3m
    log_ok "Headlamp installed."
  fi

  # Install Crossplane plugin via headlamp-plugin CLI (optional)
  if has_cmd npx; then
    log_info "Installing Headlamp Crossplane plugin ..."
    npx @kinvolk/headlamp-plugin install headlamp-plugin-crossplane 2>/dev/null \
      && log_ok "Crossplane plugin installed." \
      || log_warn "Could not install Crossplane plugin (requires Node.js). Headlamp still works without it."
  fi

  # Port-forward in background — disown so it survives script exit
  log_info "Starting port-forward on http://localhost:4466 ..."
  kubectl port-forward -n headlamp svc/headlamp 4466:80 >/dev/null 2>&1 &
  PF_PID=$!
  disown "$PF_PID"
  echo "$PF_PID" > /tmp/headlamp-portforward.pid
  sleep 2

  log_ok "Headlamp is running at ${BOLD}http://localhost:4466${RESET}"
  echo ""

  # Create service account + clusterrolebinding (idempotent) and print token
  echo -e "  ${YELLOW}Setting up Headlamp login token:${RESET}"
  kubectl create serviceaccount headlamp-admin -n headlamp \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
  kubectl create clusterrolebinding headlamp-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=headlamp:headlamp-admin \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
  echo ""
  echo -e "  ${YELLOW}Your login token (paste it into Headlamp):${RESET}"
  echo -e "  ${CYAN}$(kubectl create token headlamp-admin -n headlamp)${RESET}"
  echo ""
  echo -e "  Stop port-forward: ${CYAN}kill \$(cat /tmp/headlamp-portforward.pid)${RESET}"
  echo ""
}

# ── Kubernetes Dashboard ───────────────────────────────────────────────────────
_install_k8s_dashboard() {
  log_section "Installing Kubernetes Dashboard"

  # Add Helm repo
  if ! helm repo list 2>/dev/null | grep -q "kubernetes-dashboard"; then
    log_info "Adding Kubernetes Dashboard Helm repo ..."
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm repo update
  fi

  # Install into kubernetes-dashboard namespace
  if helm status kubernetes-dashboard -n kubernetes-dashboard &>/dev/null 2>&1; then
    log_warn "Kubernetes Dashboard already installed — skipping."
  else
    log_info "Installing Kubernetes Dashboard via Helm ..."
    kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
    helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
      --namespace kubernetes-dashboard \
      --wait --timeout 3m
    log_ok "Kubernetes Dashboard installed."
  fi

  # Create admin service account + token (idempotent)
  kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
  kubectl create clusterrolebinding dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:dashboard-admin \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

  # Port-forward in background — disown so it survives script exit
  log_info "Starting port-forward on http://localhost:8443 ..."
  kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard-kong-proxy 8443:443 >/dev/null 2>&1 &
  PF_PID=$!
  disown "$PF_PID"
  echo "$PF_PID" > /tmp/k8sdashboard-portforward.pid
  sleep 2

  log_ok "Kubernetes Dashboard is running at ${BOLD}https://localhost:8443${RESET}"
  echo ""
  echo -e "  ${YELLOW}Your login token (paste it into the Dashboard):${RESET}"
  echo -e "  ${CYAN}$(kubectl create token dashboard-admin -n kubernetes-dashboard)${RESET}"
  echo ""
  echo -e "  ${YELLOW}Note:${RESET} Your browser may warn about the self-signed certificate — proceed anyway."
  echo -e "  Stop port-forward: ${CYAN}kill \$(cat /tmp/k8sdashboard-portforward.pid)${RESET}"
  echo ""
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
case "$SELECTED_GUI" in
  headlamp)     _install_headlamp ;;
  k8sdashboard) _install_k8s_dashboard ;;
  both)         _install_headlamp; _install_k8s_dashboard ;;
esac

log_section "GUI Setup Complete"
if [[ "$SELECTED_GUI" == "headlamp" || "$SELECTED_GUI" == "both" ]]; then
  echo -e "  ${BOLD}Headlamp:${RESET}              ${CYAN}http://localhost:4466${RESET}"
fi
if [[ "$SELECTED_GUI" == "k8sdashboard" || "$SELECTED_GUI" == "both" ]]; then
  echo -e "  ${BOLD}Kubernetes Dashboard:${RESET}  ${CYAN}https://localhost:8443${RESET}"
fi
echo ""
if [[ "$SELECTED_GUI" == "headlamp" || "$SELECTED_GUI" == "both" ]]; then
  echo -e "  Stop Headlamp port-forward:"
  echo -e "    ${CYAN}kill \$(cat /tmp/headlamp-portforward.pid)${RESET}"
fi
if [[ "$SELECTED_GUI" == "k8sdashboard" || "$SELECTED_GUI" == "both" ]]; then
  echo -e "  Stop Kubernetes Dashboard port-forward:"
  echo -e "    ${CYAN}kill \$(cat /tmp/k8sdashboard-portforward.pid)${RESET}"
fi
echo ""
