#!/usr/bin/env bash
# teardown.sh — stop and remove the local Crossplane environment
#
# Usage:
#   ./teardown.sh                        # interactive — asks what to remove
#   CLUSTER_NAME=my-cluster ./teardown.sh
#   ./teardown.sh --all                  # remove everything without prompting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

CLUSTER_NAME="${CLUSTER_NAME:-crossplane-local}"
REMOVE_ALL=false
[[ "${1:-}" == "--all" ]] && REMOVE_ALL=true

# ── Banner ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${RED}  Crossplane Local — Teardown${RESET}\n"

# ── Helpers ────────────────────────────────────────────────────────────────────
_confirm() {
  local msg="$1"
  if [[ "$REMOVE_ALL" == true ]]; then return 0; fi
  ask_yes_no "$msg" "y"
}

_remove_kind_cluster() {
  if ! has_cmd kind; then return; fi
  local clusters
  clusters=$(kind get clusters 2>/dev/null || true)
  if echo "$clusters" | grep -q "^${CLUSTER_NAME}$"; then
    if _confirm "Delete kind cluster '${CLUSTER_NAME}'?"; then
      log_info "Deleting kind cluster '${CLUSTER_NAME}' ..."
      kind delete cluster --name "${CLUSTER_NAME}"
      log_ok "kind cluster '${CLUSTER_NAME}' deleted."
    fi
  else
    log_info "No kind cluster named '${CLUSTER_NAME}' found — skipping."
  fi
}

_remove_k3d_cluster() {
  if ! has_cmd k3d; then return; fi
  if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
    if _confirm "Delete k3d cluster '${CLUSTER_NAME}'?"; then
      log_info "Deleting k3d cluster '${CLUSTER_NAME}' ..."
      k3d cluster delete "${CLUSTER_NAME}"
      log_ok "k3d cluster '${CLUSTER_NAME}' deleted."
    fi
  else
    log_info "No k3d cluster named '${CLUSTER_NAME}' found — skipping."
  fi
}

_stop_colima() {
  if ! has_cmd colima; then return; fi
  if colima status 2>/dev/null | grep -q "Running"; then
    if _confirm "Stop Colima VM?"; then
      log_info "Stopping Colima ..."
      colima stop
      log_ok "Colima stopped."
    fi
  else
    log_info "Colima is not running — skipping."
  fi
}

_clean_kubeconfig() {
  # Remove stale kind-/k3d- contexts and clusters from ~/.kube/config
  log_section "Cleaning kubeconfig"

  local cleaned=0
  for ctx in $(kubectl config get-contexts -o name 2>/dev/null | grep -E "^(kind|k3d)-${CLUSTER_NAME}$" || true); do
    if _confirm "Remove kubeconfig context '${ctx}'?"; then
      kubectl config delete-context "${ctx}" &>/dev/null || true
      kubectl config delete-cluster "${ctx}" &>/dev/null || true
      kubectl config unset "users.${ctx}" &>/dev/null || true
      log_ok "Removed context '${ctx}' from kubeconfig."
      (( cleaned++ )) || true
    fi
  done

  (( cleaned == 0 )) && log_info "No stale Crossplane contexts found in kubeconfig."

  # If current context was deleted, switch to a safe default
  local current
  current=$(kubectl config current-context 2>/dev/null || true)
  if [[ -z "$current" ]] || ! kubectl config get-contexts "$current" &>/dev/null 2>&1; then
    local first_ctx
    first_ctx=$(kubectl config get-contexts -o name 2>/dev/null | head -1 || true)
    if [[ -n "$first_ctx" ]]; then
      kubectl config use-context "$first_ctx" &>/dev/null || true
      log_info "Switched kubectl context to '${first_ctx}'."
    fi
  fi
}

_clean_docker_images() {
  if ! has_cmd docker || ! docker info &>/dev/null 2>&1; then return; fi
  if _confirm "Remove unused Docker images (docker image prune)?"; then
    log_info "Pruning unused Docker images ..."
    docker image prune -f
    log_ok "Unused Docker images removed."
  fi
}

_clean_helm_repos() {
  if ! has_cmd helm; then return; fi
  if helm repo list 2>/dev/null | grep -q "crossplane-stable"; then
    if _confirm "Remove crossplane-stable Helm repo?"; then
      helm repo remove crossplane-stable
      log_ok "crossplane-stable Helm repo removed."
    fi
  fi
}

# ── Main flow ──────────────────────────────────────────────────────────────────
log_section "Detecting Running Environment"

local_kind=false
local_k3d=false

if has_cmd kind && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_info "Found kind cluster:  ${BOLD}${CLUSTER_NAME}${RESET}"
  local_kind=true
fi

if has_cmd k3d && k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  log_info "Found k3d cluster:   ${BOLD}${CLUSTER_NAME}${RESET}"
  local_k3d=true
fi

if has_cmd colima && colima status 2>/dev/null | grep -q "Running"; then
  log_info "Found Colima VM:     ${BOLD}running${RESET}"
fi

if [[ "$local_kind" == false && "$local_k3d" == false ]]; then
  log_warn "No local Crossplane cluster named '${CLUSTER_NAME}' is running."
  echo -e "  Use ${BOLD}CLUSTER_NAME=<name> ./teardown.sh${RESET} to target a different cluster."
  echo ""
fi

log_section "Cleanup"
_remove_kind_cluster
_remove_k3d_cluster
_stop_colima
_clean_kubeconfig
_clean_helm_repos
_clean_docker_images

log_section "Done"
log_ok "Local Crossplane environment '${CLUSTER_NAME}' has been removed."
echo ""
echo -e "  To set up again:"
echo -e "    ${CYAN}./setup.sh${RESET}"
echo ""
