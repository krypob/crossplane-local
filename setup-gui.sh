#!/usr/bin/env bash
# setup-gui.sh — optional GUI dashboard for the local Crossplane environment
#
# Available dashboards:
#   1) Headlamp   — modern Kubernetes web UI with Crossplane plugin (open source)
#   2) Upbound Console — official Crossplane UI by Upbound (free for local use)
#
# Usage:
#   ./setup-gui.sh                  # interactive — choose which GUI to install
#   GUI=headlamp ./setup-gui.sh     # skip prompt
#   GUI=upbound  ./setup-gui.sh

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
  echo -e "  ${BOLD}2) Upbound Console${RESET}  — official Crossplane web UI"
  echo -e "     Connects to your local cluster via the 'up' CLI."
  echo -e "     Free for local use. Requires an Upbound account (free)."
  echo -e "     Access: https://console.upbound.io\n"
  echo -e "  ${BOLD}3) Both${RESET}\n"

  while true; do
    read -rp "$(echo -e "${YELLOW}  Choice [1-3]: ${RESET}")" choice
    case "${choice:-}" in
      1|headlamp)  SELECTED_GUI="headlamp"; return ;;
      2|upbound)   SELECTED_GUI="upbound";  return ;;
      3|both)      SELECTED_GUI="both";     return ;;
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

  # Port-forward in background
  log_info "Starting port-forward on http://localhost:4466 ..."
  kubectl port-forward -n headlamp svc/headlamp 4466:80 &>/dev/null &
  PF_PID=$!
  echo "$PF_PID" > /tmp/headlamp-portforward.pid
  sleep 2

  log_ok "Headlamp is running at ${BOLD}http://localhost:4466${RESET}"
  echo ""

  # Print access token
  echo -e "  ${YELLOW}To log in, create a service account token:${RESET}"
  echo -e "  ${CYAN}kubectl create serviceaccount headlamp-admin -n headlamp${RESET}"
  echo -e "  ${CYAN}kubectl create clusterrolebinding headlamp-admin \\${RESET}"
  echo -e "  ${CYAN}    --clusterrole=cluster-admin --serviceaccount=headlamp:headlamp-admin${RESET}"
  echo -e "  ${CYAN}kubectl create token headlamp-admin -n headlamp${RESET}"
  echo ""
  echo -e "  Stop port-forward: ${CYAN}kill \$(cat /tmp/headlamp-portforward.pid)${RESET}"
  echo ""
}

# ── Upbound Console ────────────────────────────────────────────────────────────
_install_upbound_console() {
  log_section "Connecting to Upbound Console"

  if ! has_cmd up; then
    log_error "'up' CLI not found. Run ./setup.sh first to install it."
    exit 1
  fi

  echo -e "  The Upbound Console is a hosted web UI at ${BOLD}https://console.upbound.io${RESET}"
  echo -e "  It connects securely to your local cluster via the 'up' CLI."
  echo -e "  A ${BOLD}free Upbound account${RESET} is required.\n"

  if ! up organization list &>/dev/null 2>&1; then
    log_info "You need to log in to Upbound first."
    echo -e "  ${CYAN}up login${RESET}"
    echo ""
    read -rp "$(echo -e "${YELLOW}  Press Enter after logging in with 'up login', or Ctrl+C to skip: ${RESET}")"
  fi

  log_info "Connecting local cluster to Upbound Console ..."
  echo -e "  Run the following command (replace <org> with your Upbound org name):"
  echo ""
  echo -e "  ${CYAN}up space connect --cluster-name crossplane-local${RESET}"
  echo ""
  echo -e "  Then open: ${BOLD}https://console.upbound.io${RESET}"
  echo ""
  log_ok "Upbound Console setup guide complete."
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
case "$SELECTED_GUI" in
  headlamp) _install_headlamp ;;
  upbound)  _install_upbound_console ;;
  both)     _install_headlamp; _install_upbound_console ;;
esac

log_section "GUI Setup Complete"
if [[ "$SELECTED_GUI" == "headlamp" || "$SELECTED_GUI" == "both" ]]; then
  echo -e "  ${BOLD}Headlamp:${RESET}        ${CYAN}http://localhost:4466${RESET}"
fi
if [[ "$SELECTED_GUI" == "upbound" || "$SELECTED_GUI" == "both" ]]; then
  echo -e "  ${BOLD}Upbound Console:${RESET} ${CYAN}https://console.upbound.io${RESET}"
fi
echo ""
echo -e "  To stop Headlamp port-forward:"
echo -e "    ${CYAN}kill \$(cat /tmp/headlamp-portforward.pid)${RESET}"
echo ""
