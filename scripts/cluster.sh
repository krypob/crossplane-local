#!/usr/bin/env bash
# scripts/cluster.sh — create cluster (kind or k3d) and install Crossplane via helm

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CLUSTER_NAME="${CLUSTER_NAME:-crossplane-local}"
CROSSPLANE_NAMESPACE="${CROSSPLANE_NAMESPACE:-crossplane-system}"
CROSSPLANE_CHART_VERSION="${CROSSPLANE_CHART_VERSION:-}"
KIND_CONFIG_PATH="${KIND_CONFIG_PATH:-$(dirname "${BASH_SOURCE[0]}")/../configs/kind-config.yaml}"
K3D_CONFIG_PATH="${K3D_CONFIG_PATH:-$(dirname "${BASH_SOURCE[0]}")/../configs/k3d-config.yaml}"

# ── kind cluster (standard stack) ────────────────────────────────────────────
_create_kind_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_warn "kind cluster '${CLUSTER_NAME}' already exists — skipping creation."
    kubectl config use-context "kind-${CLUSTER_NAME}" &>/dev/null
    return 0
  fi
  log_info "Creating kind cluster '${CLUSTER_NAME}' ..."
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${KIND_CONFIG_PATH}" \
    --wait 120s || { log_error "Failed to create kind cluster."; exit 1; }
  log_ok "Cluster '${CLUSTER_NAME}' created."
  kubectl config use-context "kind-${CLUSTER_NAME}"
  log_ok "kubectl context set to kind-${CLUSTER_NAME}."
}

# ── k3d cluster (lightweight stack) ──────────────────────────────────────────
_create_k3d_cluster() {
  if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
    log_warn "k3d cluster '${CLUSTER_NAME}' already exists — skipping creation."
    kubectl config use-context "k3d-${CLUSTER_NAME}" &>/dev/null
    return 0
  fi
  log_info "Creating k3d cluster '${CLUSTER_NAME}' (k3s — lightweight) ..."
  k3d cluster create \
    --config "${K3D_CONFIG_PATH}" \
    --wait || { log_error "Failed to create k3d cluster."; exit 1; }
  log_ok "Cluster '${CLUSTER_NAME}' created."
  kubectl config use-context "k3d-${CLUSTER_NAME}"
  log_ok "kubectl context set to k3d-${CLUSTER_NAME}."
}

# ── Helm repo ─────────────────────────────────────────────────────────────────
_setup_helm_repos() {
  log_section "Helm Repositories"
  if helm repo list 2>/dev/null | grep -q "crossplane-stable"; then
    log_ok "crossplane-stable repo already added."
  else
    log_info "Adding crossplane-stable Helm repo ..."
    helm repo add crossplane-stable https://charts.crossplane.io/stable
    log_ok "Repo added."
  fi
  log_info "Updating Helm repos ..."
  helm repo update
  log_ok "Repos up to date."
}

# ── Crossplane install ────────────────────────────────────────────────────────
_install_crossplane() {
  log_section "Installing Crossplane"
  local version_flag=""
  [[ -n "$CROSSPLANE_CHART_VERSION" ]] && version_flag="--version ${CROSSPLANE_CHART_VERSION}"

  if helm status crossplane -n "${CROSSPLANE_NAMESPACE}" &>/dev/null; then
    log_warn "Crossplane already installed in '${CROSSPLANE_NAMESPACE}'. Skipping."
    return 0
  fi

  log_info "Creating namespace '${CROSSPLANE_NAMESPACE}' ..."
  kubectl create namespace "${CROSSPLANE_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  log_info "Installing Crossplane via Helm (this may take a minute) ..."
  # shellcheck disable=SC2086
  helm install crossplane crossplane-stable/crossplane \
    --namespace "${CROSSPLANE_NAMESPACE}" \
    --set args='{--debug}' \
    --wait \
    --timeout 5m \
    $version_flag || { log_error "Helm install of Crossplane failed."; exit 1; }
  log_ok "Crossplane installed."
}

# ── Verify ────────────────────────────────────────────────────────────────────
_verify_crossplane() {
  log_section "Verifying Installation"
  log_info "Waiting for Crossplane pods to be ready ..."
  if kubectl wait pod \
    --for=condition=Ready \
    --selector=app=crossplane \
    --namespace="${CROSSPLANE_NAMESPACE}" \
    --timeout=120s; then
    log_ok "Crossplane pods are running."
  else
    log_warn "Pods not ready within timeout — check: kubectl get pods -n ${CROSSPLANE_NAMESPACE}"
  fi

  echo ""
  log_info "Pod status:"
  kubectl get pods -n "${CROSSPLANE_NAMESPACE}"
  echo ""
  log_info "Installed CRDs (first 10):"
  kubectl get crds | grep crossplane | head -10
  echo ""

  local ctx
  ctx=$(kubectl config current-context)
  log_ok "Crossplane is ready in cluster '${CLUSTER_NAME}'!"
  echo ""
  echo -e "  ${BOLD}Useful commands:${RESET}"
  echo -e "    kubectl get pods -n ${CROSSPLANE_NAMESPACE}"
  echo -e "    kubectl get crds | grep crossplane"
  echo -e "    kubectl api-resources | grep crossplane.io"
  echo ""
  echo -e "  ${BOLD}Tear down:${RESET}"
  if [[ "$ctx" == k3d-* ]]; then
    echo -e "    k3d cluster delete ${CLUSTER_NAME}"
  else
    echo -e "    kind delete cluster --name ${CLUSTER_NAME}"
  fi
  echo ""
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
setup_cluster() {
  local stack="${1:-standard}"

  log_section "Kubernetes Cluster"

  if [[ "$stack" == "lightweight" ]]; then
    _create_k3d_cluster
  else
    _create_kind_cluster
  fi

  _setup_helm_repos
  _install_crossplane
  _verify_crossplane
}
