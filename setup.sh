#!/usr/bin/env bash
# setup.sh — one-command Crossplane local environment setup (macOS / Linux)
#
# Usage:
#   ./setup.sh                             # fully interactive
#   OS=macos STACK=lightweight ./setup.sh  # skip prompts
#
# Optional env overrides:
#   OS=macos|linux               skip OS prompt
#   STACK=standard|lightweight   skip stack prompt
#   SKIP_CHECKS=1                skip resource checks
#   CLUSTER_NAME=my-cluster
#   CROSSPLANE_CHART_VERSION=2.2.0
#   COLIMA_CPU=2  COLIMA_MEMORY=4  COLIMA_DISK=60  (lightweight only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/requirements.sh"
source "${SCRIPT_DIR}/scripts/install.sh"
source "${SCRIPT_DIR}/scripts/cluster.sh"

# ── Banner ─────────────────────────────────────────────────────────────────────
print_banner

# ══════════════════════════════════════════════════════════════════════════════
# Step 1 — OS selection
# ══════════════════════════════════════════════════════════════════════════════
log_section "Step 1 — Operating System"

# Sets global SELECTED_OS
_select_os() {
  if [[ -n "${OS:-}" ]]; then
    SELECTED_OS="$OS"
    return
  fi

  local detected
  case "$(uname -s)" in
    Darwin) detected="macos" ;;
    Linux)  detected="linux" ;;
    *)      detected="unknown" ;;
  esac

  echo -e "  Auto-detected: ${BOLD}${detected}${RESET}\n"
  echo -e "  Confirm your OS:"
  echo -e "    1) macOS"
  echo -e "    2) Linux"
  echo -e "    3) Windows  (prints instructions and exits)\n"

  while true; do
    read -rp "$(echo -e "${YELLOW}  Choice [1-3] (Enter = auto-detected): ${RESET}")" choice
    case "${choice:-}" in
      1|macos|mac)   SELECTED_OS="macos";   return ;;
      2|linux)       SELECTED_OS="linux";   return ;;
      3|windows|win) SELECTED_OS="windows"; return ;;
      "")
        if [[ "$detected" != "unknown" ]]; then
          SELECTED_OS="$detected"
          return
        fi
        echo "  Please enter 1, 2, or 3."
        ;;
      *) echo "  Invalid — enter 1, 2, or 3." ;;
    esac
  done
}

SELECTED_OS=""
_select_os
log_ok "OS: ${BOLD}${SELECTED_OS}${RESET}"

# Windows — hand off and exit
if [[ "$SELECTED_OS" == "windows" ]]; then
  log_warn "Windows detected — run the PowerShell script instead:"
  echo ""
  echo -e "  ${BOLD}Open PowerShell as Administrator:${RESET}"
  echo -e "  ${CYAN}  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser${RESET}"
  echo -e "  ${CYAN}  .\\setup.ps1${RESET}"
  echo ""
  echo -e "  Inside WSL 2? Re-run this script from your WSL terminal."
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# Step 2 — Stack selection
# ══════════════════════════════════════════════════════════════════════════════
log_section "Step 2 — Container Runtime & Kubernetes Stack"

# Sets global SELECTED_STACK
_select_stack() {
  if [[ -n "${STACK:-}" ]]; then
    SELECTED_STACK="$STACK"
    return
  fi

  echo -e "  Choose how to run Kubernetes locally:\n"
  echo -e "  ${BOLD}1) Standard${RESET}    — Docker + kind"
  echo -e "     Full Kubernetes. Requires ${BOLD}8 GiB RAM${RESET} / 4 CPU cores."
  echo -e "     Best if you already have Docker Desktop installed.\n"
  echo -e "  ${BOLD}2) Lightweight${RESET} — Colima + k3d  ${GREEN}(recommended for laptops)${RESET}"
  echo -e "     Uses k3s — certified K8s with ~70%% less RAM/CPU."
  echo -e "     Requires only ${BOLD}2 GiB RAM${RESET} / 2 CPU cores. No Docker Desktop needed."
  if [[ "$SELECTED_OS" == "linux" ]]; then
    echo -e "     On Linux: uses Docker Engine (no desktop GUI) + k3d.\n"
  else
    echo -e "     Installs Colima automatically via Homebrew.\n"
  fi

  while true; do
    read -rp "$(echo -e "${YELLOW}  Choice [1-2] (default: 2 lightweight): ${RESET}")" choice
    case "${choice:-2}" in
      1|standard)    SELECTED_STACK="standard";    return ;;
      2|lightweight) SELECTED_STACK="lightweight"; return ;;
      *) echo "  Please enter 1 or 2." ;;
    esac
  done
}

SELECTED_STACK=""
_select_stack
export STACK="$SELECTED_STACK"

if [[ "$SELECTED_STACK" == "lightweight" ]]; then
  log_ok "Stack: ${BOLD}${GREEN}Lightweight${RESET} (Colima + k3d/k3s)"
else
  log_ok "Stack: ${BOLD}Standard${RESET} (Docker + kind)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Step 3 — Show requirements
# ══════════════════════════════════════════════════════════════════════════════
log_section "Step 3 — Minimum Requirements"
show_requirements "$SELECTED_OS" "$SELECTED_STACK"

if ! ask_yes_no "Requirements look good — continue with setup?"; then
  log_warn "Setup cancelled."
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# Step 4 — Check system resources (soft — warns but never hard-blocks)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "${SKIP_CHECKS:-0}" != "1" ]]; then
  check_system_resources "$SELECTED_OS" "$SELECTED_STACK"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Step 5 — Install tools
# ══════════════════════════════════════════════════════════════════════════════
install_tools "$SELECTED_OS" "$SELECTED_STACK"

# ══════════════════════════════════════════════════════════════════════════════
# Step 6 — Create cluster & install Crossplane
# ══════════════════════════════════════════════════════════════════════════════
setup_cluster "$SELECTED_STACK"

# ══════════════════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════════════════
log_section "Setup Complete"
echo -e "  ${GREEN}${BOLD}Your local Crossplane environment is ready!${RESET}"
echo ""
echo -e "  Stack   : ${BOLD}${SELECTED_STACK}${RESET}"
echo -e "  Cluster : ${BOLD}${CLUSTER_NAME:-crossplane-local}${RESET}"
if [[ "$SELECTED_STACK" == "lightweight" ]]; then
  echo -e "  Context : ${BOLD}k3d-${CLUSTER_NAME:-crossplane-local}${RESET}"
else
  echo -e "  Context : ${BOLD}kind-${CLUSTER_NAME:-crossplane-local}${RESET}"
fi
echo ""
echo -e "  Quick-start:"
echo -e "    ${CYAN}kubectl get pods -n ${CROSSPLANE_NAMESPACE:-crossplane-system}${RESET}"
echo -e "    ${CYAN}kubectl get crds | grep crossplane${RESET}"
echo ""
echo -e "  Optional next steps:"
echo -e "    ${CYAN}./setup-gui.sh${RESET}               # install a visual dashboard (Headlamp / Upbound)"
echo -e "    ${CYAN}./examples/apply.sh${RESET}          # try example Compositions"
echo ""
echo -e "  Tear down (removes cluster, kubeconfig context, optional image prune):"
echo -e "    ${CYAN}./teardown.sh${RESET}        # interactive"
echo -e "    ${CYAN}./teardown.sh --all${RESET}  # remove everything without prompts"
echo ""

# ── Optional GUI prompt ────────────────────────────────────────────────────────
if [[ "${SKIP_GUI:-0}" != "1" ]] && ask_yes_no "Would you like to install a GUI dashboard now?" "n"; then
  bash "${SCRIPT_DIR}/setup-gui.sh"
fi
