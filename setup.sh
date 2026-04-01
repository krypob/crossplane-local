#!/usr/bin/env bash
# setup.sh — one-command Crossplane local environment setup (macOS / Linux)
#
# Usage:
#   ./setup.sh                     # interactive
#   OS=macos ./setup.sh            # skip OS prompt
#   SKIP_CHECKS=1 ./setup.sh       # skip resource checks
#   CLUSTER_NAME=my-cluster ./setup.sh
#   CROSSPLANE_CHART_VERSION=1.17.0 ./setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source helpers ─────────────────────────────────────────────────────────────
source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/requirements.sh"
source "${SCRIPT_DIR}/scripts/install.sh"
source "${SCRIPT_DIR}/scripts/cluster.sh"

# ── Banner ─────────────────────────────────────────────────────────────────────
print_banner

# ── Step 1 — OS selection ──────────────────────────────────────────────────────
log_section "Step 1 — Operating System"

detect_os() {
  local detected
  case "$(uname -s)" in
    Darwin) detected="macos" ;;
    Linux)  detected="linux" ;;
    *)      detected="unknown" ;;
  esac
  echo "$detected"
}

select_os() {
  local auto_detected
  auto_detected="$(detect_os)"

  if [[ -n "${OS:-}" ]]; then
    echo "$OS"
    return
  fi

  echo -e "  Auto-detected OS: ${BOLD}${auto_detected}${RESET}"
  echo ""
  echo -e "  Please confirm your operating system:"
  echo -e "    1) macOS"
  echo -e "    2) Linux"
  echo -e "    3) Windows  (will print Windows instructions and exit)"
  echo ""

  local choice
  while true; do
    read -rp "$(echo -e "${YELLOW}  Enter choice [1-3] (default: auto-detected): ${RESET}")" choice
    choice="${choice:-}"

    case "$choice" in
      1|macos|MacOS|mac|Mac)   echo "macos"; return ;;
      2|linux|Linux)           echo "linux"; return ;;
      3|windows|Windows|win)   echo "windows"; return ;;
      "")
        if [[ "$auto_detected" != "unknown" ]]; then
          echo "$auto_detected"
          return
        fi
        echo "  Please enter 1, 2, or 3."
        ;;
      *) echo "  Invalid choice. Enter 1, 2, or 3." ;;
    esac
  done
}

SELECTED_OS="$(select_os)"
log_ok "Selected OS: ${BOLD}${SELECTED_OS}${RESET}"

# ── Windows — print instructions and exit ─────────────────────────────────────
if [[ "$SELECTED_OS" == "windows" ]]; then
  log_warn "Windows detected — please run the PowerShell script instead:"
  echo ""
  echo -e "  ${BOLD}Open PowerShell as Administrator and run:${RESET}"
  echo -e "  ${CYAN}  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser${RESET}"
  echo -e "  ${CYAN}  .\\setup.ps1${RESET}"
  echo ""
  echo -e "  Or, if you are inside WSL 2, re-run this script from your WSL terminal."
  exit 0
fi

# ── Step 2 — Show requirements ────────────────────────────────────────────────
log_section "Step 2 — Minimum Requirements"
show_requirements "$SELECTED_OS"

if ! ask_yes_no "Do you meet the requirements above and want to continue?"; then
  echo ""
  log_warn "Setup cancelled. Ensure you meet the requirements and try again."
  exit 0
fi

# ── Step 3 — Check system resources ──────────────────────────────────────────
if [[ "${SKIP_CHECKS:-0}" != "1" ]]; then
  if ! check_system_resources "$SELECTED_OS"; then
    echo ""
    if ! ask_yes_no "Resource checks failed. Continue anyway (not recommended)?"; then
      log_warn "Setup cancelled."
      exit 1
    fi
  fi
fi

# ── Step 4 — Install tools ────────────────────────────────────────────────────
install_tools "$SELECTED_OS"

# ── Step 5 — Create cluster & install Crossplane ──────────────────────────────
setup_cluster

# ── Done ──────────────────────────────────────────────────────────────────────
log_section "Setup Complete"
echo -e "  ${GREEN}${BOLD}Your local Crossplane environment is ready!${RESET}"
echo ""
echo -e "  Cluster : ${BOLD}${CLUSTER_NAME:-crossplane-local}${RESET}"
echo -e "  Context : ${BOLD}kind-${CLUSTER_NAME:-crossplane-local}${RESET}"
echo ""
echo -e "  Quick-start commands:"
echo -e "    ${CYAN}kubectl get pods -n ${CROSSPLANE_NAMESPACE:-crossplane-system}${RESET}"
echo -e "    ${CYAN}kubectl get crds | grep crossplane${RESET}"
echo ""
echo -e "  To tear down:"
echo -e "    ${CYAN}kind delete cluster --name ${CLUSTER_NAME:-crossplane-local}${RESET}"
echo ""
