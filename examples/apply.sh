#!/usr/bin/env bash
# examples/apply.sh — install provider + compositions + optionally apply a claim
#
# Usage:
#   ./examples/apply.sh           # install provider, compositions, ask about claim
#   ./examples/apply.sh --all     # install everything including the example claim

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"

APPLY_ALL=false
[[ "${1:-}" == "--all" ]] && APPLY_ALL=true

log_section "Crossplane Examples — Apply"

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! kubectl cluster-info &>/dev/null 2>&1; then
  log_error "No Kubernetes cluster reachable. Run ./setup.sh first."
  exit 1
fi

if ! kubectl get namespace crossplane-system &>/dev/null 2>&1; then
  log_error "Crossplane is not installed. Run ./setup.sh first."
  exit 1
fi

# ── Step 1: Provider ──────────────────────────────────────────────────────────
log_section "Step 1 — Installing provider-kubernetes"

kubectl apply -f "${SCRIPT_DIR}/01-provider/provider-kubernetes.yaml"
log_info "Waiting for provider-kubernetes to become healthy (up to 3 min) ..."

for i in $(seq 1 36); do
  status=$(kubectl get provider provider-kubernetes \
    -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null || echo "")
  if [[ "$status" == "True" ]]; then
    log_ok "provider-kubernetes is healthy."
    break
  fi
  if (( i == 36 )); then
    log_warn "Provider not healthy after 3 min — check: kubectl get provider provider-kubernetes"
  fi
  sleep 5
done

kubectl apply -f "${SCRIPT_DIR}/01-provider/providerconfig-kubernetes.yaml"
log_ok "ProviderConfig 'default' applied."

# ── Step 2: Compositions ──────────────────────────────────────────────────────
log_section "Step 2 — Applying XRD + Composition"

kubectl apply -f "${SCRIPT_DIR}/02-compositions/xnamespace/xrd.yaml"
log_ok "XRD applied."

kubectl apply -f "${SCRIPT_DIR}/02-compositions/xnamespace/composition.yaml"
log_ok "Composition applied."

log_info "Waiting for XRD to become established ..."
kubectl wait xrd xnamespaces.example.crossplane.io \
  --for=condition=Established --timeout=60s
log_ok "XRD established — AppNamespace API is ready."

# ── Step 3: Example Claim (optional) ─────────────────────────────────────────
log_section "Step 3 — Example Claim"

if [[ "$APPLY_ALL" == true ]] || ask_yes_no "Apply the example AppNamespace claim?"; then
  kubectl apply -f "${SCRIPT_DIR}/03-claims/my-app-namespace.yaml"
  log_ok "Claim applied."
  echo ""
  log_info "Watching claim status (Ctrl+C to stop) ..."
  sleep 2
  kubectl get appnamespace my-app -n default
  echo ""
  log_info "Once synced, check the provisioned resources:"
  echo -e "    ${CYAN}kubectl get namespace my-app-dev${RESET}"
  echo -e "    ${CYAN}kubectl get resourcequota -n my-app-dev${RESET}"
  echo -e "    ${CYAN}kubectl get appnamespace my-app -n default${RESET}"
else
  echo ""
  log_info "Skipped. Apply the claim manually:"
  echo -e "    ${CYAN}kubectl apply -f examples/03-claims/my-app-namespace.yaml${RESET}"
fi

echo ""
log_ok "Examples ready. Try the new API:"
echo -e "    ${CYAN}kubectl get appnamespace${RESET}"
echo -e "    ${CYAN}kubectl get xnamespace${RESET}"
echo -e "    ${CYAN}kubectl get composition${RESET}"
echo ""
echo -e "  Remove everything:"
echo -e "    ${CYAN}./examples/destroy.sh${RESET}"
echo ""
