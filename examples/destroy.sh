#!/usr/bin/env bash
# examples/destroy.sh — remove all example resources in safe order
#
# Usage:
#   ./examples/destroy.sh           # interactive
#   ./examples/destroy.sh --all     # remove everything without prompting

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"

REMOVE_ALL=false
[[ "${1:-}" == "--all" ]] && REMOVE_ALL=true

_confirm() { [[ "$REMOVE_ALL" == true ]] || ask_yes_no "$1"; }

log_section "Crossplane Examples — Destroy"

# ── Claims first (must delete before XRD/Composition) ────────────────────────
log_section "Step 1 — Removing Claims"
if kubectl get appnamespace my-app -n default &>/dev/null 2>&1; then
  if _confirm "Delete AppNamespace claim 'my-app'?"; then
    kubectl delete -f "${SCRIPT_DIR}/03-claims/my-app-namespace.yaml" --ignore-not-found
    log_info "Waiting for managed resources to be deleted ..."
    kubectl wait appnamespace my-app -n default --for=delete --timeout=60s 2>/dev/null || true
    log_ok "Claim and managed resources deleted."
  fi
else
  log_info "No active claims found — skipping."
fi

# ── Compositions ──────────────────────────────────────────────────────────────
log_section "Step 2 — Removing Compositions + XRD"
if _confirm "Delete Composition and XRD?"; then
  kubectl delete -f "${SCRIPT_DIR}/02-compositions/xnamespace/composition.yaml" --ignore-not-found
  kubectl delete -f "${SCRIPT_DIR}/02-compositions/xnamespace/xrd.yaml" --ignore-not-found
  log_ok "Composition and XRD deleted."
fi

# ── Provider ──────────────────────────────────────────────────────────────────
log_section "Step 3 — Removing Provider"
if _confirm "Delete ProviderConfig and provider-kubernetes?"; then
  kubectl delete -f "${SCRIPT_DIR}/01-provider/providerconfig-kubernetes.yaml" --ignore-not-found
  kubectl delete -f "${SCRIPT_DIR}/01-provider/provider-kubernetes.yaml" --ignore-not-found
  log_ok "Provider removed."
fi

echo ""
log_ok "All example resources removed."
echo ""
