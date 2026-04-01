#!/usr/bin/env bash
# update.sh — upgrade Crossplane and installed providers in-place
#
# Usage:
#   ./update.sh                        # interactive — shows current vs latest, asks to confirm
#   ./update.sh --yes                  # non-interactive, upgrade everything
#   ./update.sh --crossplane-only      # upgrade Crossplane chart only
#   ./update.sh --providers-only       # upgrade installed providers only
#   CROSSPLANE_CHART_VERSION=2.3.0 ./update.sh  # pin a specific version

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

CROSSPLANE_NAMESPACE="${CROSSPLANE_NAMESPACE:-crossplane-system}"
AUTO_YES=false
CROSSPLANE_ONLY=false
PROVIDERS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --yes)              AUTO_YES=true ;;
    --crossplane-only)  CROSSPLANE_ONLY=true ;;
    --providers-only)   PROVIDERS_ONLY=true ;;
  esac
done

_confirm() { [[ "$AUTO_YES" == true ]] || ask_yes_no "$1"; }

# ── Banner ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}  Crossplane Local — Updater${RESET}\n"

# ── Preflight ──────────────────────────────────────────────────────────────────
if ! kubectl cluster-info &>/dev/null 2>&1; then
  log_error "No Kubernetes cluster reachable. Run ./setup.sh first."
  exit 1
fi

if ! helm status crossplane -n "$CROSSPLANE_NAMESPACE" &>/dev/null 2>&1; then
  log_error "Crossplane is not installed. Run ./setup.sh first."
  exit 1
fi

# ── Refresh Helm repos ────────────────────────────────────────────────────────
log_section "Refreshing Helm Repos"
helm repo update
log_ok "Repos refreshed."

# ══════════════════════════════════════════════════════════════════════════════
# Crossplane chart upgrade
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$PROVIDERS_ONLY" == false ]]; then
  log_section "Crossplane Chart"

  current_version=$(helm list -n "$CROSSPLANE_NAMESPACE" \
    --filter "^crossplane$" -o json 2>/dev/null \
    | grep -o '"chart":"crossplane-[^"]*"' \
    | grep -o '[0-9][0-9.]*' | head -1 || echo "unknown")

  latest_version=$(helm search repo crossplane-stable/crossplane \
    --output json 2>/dev/null \
    | grep -o '"version":"[^"]*"' | head -1 \
    | grep -o '[0-9][0-9.]*' || echo "unknown")

  target_version="${CROSSPLANE_CHART_VERSION:-$latest_version}"

  echo -e "  Installed : ${BOLD}${current_version}${RESET}"
  echo -e "  Available : ${BOLD}${latest_version}${RESET}"
  echo -e "  Target    : ${BOLD}${target_version}${RESET}"
  echo ""

  if [[ "$current_version" == "$target_version" ]]; then
    log_ok "Crossplane is already at version ${target_version}."
  elif _confirm "Upgrade Crossplane from ${current_version} to ${target_version}?"; then
    log_info "Upgrading Crossplane ..."
    version_flag=""
    [[ -n "${CROSSPLANE_CHART_VERSION:-}" ]] && version_flag="--version ${CROSSPLANE_CHART_VERSION}"

    # shellcheck disable=SC2086
    helm upgrade crossplane crossplane-stable/crossplane \
      --namespace "$CROSSPLANE_NAMESPACE" \
      --reuse-values \
      --wait \
      --timeout 5m \
      $version_flag

    log_ok "Crossplane upgraded to $(helm list -n "$CROSSPLANE_NAMESPACE" \
      --filter '^crossplane$' -o json | grep -o '"chart":"crossplane-[^"]*"' \
      | grep -o '[0-9][0-9.]*' | head -1)."
  else
    log_info "Skipping Crossplane upgrade."
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Provider upgrades
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$CROSSPLANE_ONLY" == false ]]; then
  log_section "Installed Providers"

  providers=$(kubectl get provider -o json 2>/dev/null \
    | grep -o '"name":"[^"]*"' | grep -v '"name":"provider-' | \
    grep -v 'revision\|config\|package' || true)

  provider_list=$(kubectl get provider -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.package}{"\n"}{end}' 2>/dev/null || true)

  if [[ -z "$provider_list" ]]; then
    log_info "No providers installed — skipping."
  else
    echo -e "  Installed providers:\n"
    echo "$provider_list" | while IFS=$'\t' read -r name package; do
      current_tag=$(echo "$package" | grep -o ':[^:]*$' | tr -d ':')
      echo -e "    ${BOLD}${name}${RESET}  →  ${package}"
    done
    echo ""

    if _confirm "Upgrade all providers to their latest patch version?"; then
      echo "$provider_list" | while IFS=$'\t' read -r name package; do
        # Strip the tag and re-apply latest — Crossplane auto-resolves latest within channel
        base_image=$(echo "$package" | sed 's/:[^:]*$//')
        log_info "Patching provider '${name}' → ${base_image}:latest ..."
        kubectl patch provider "$name" \
          --type=merge \
          -p "{\"spec\":{\"package\":\"${base_image}:latest\"}}" \
          && log_ok "${name} patched — Crossplane will pull latest revision." \
          || log_warn "Failed to patch ${name}."
      done

      log_info "Waiting for providers to become healthy ..."
      sleep 5
      kubectl get provider 2>/dev/null || true
    else
      log_info "Skipping provider upgrades."
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Tools update check
# ══════════════════════════════════════════════════════════════════════════════
log_section "CLI Tools — Version Check"

_check_tool() {
  local name="$1" cmd="$2" version_cmd="$3"
  if has_cmd "$cmd"; then
    local ver; ver=$(eval "$version_cmd" 2>/dev/null | head -1 || echo "unknown")
    log_info "${name}: ${ver}"
  else
    log_warn "${name}: not installed"
  fi
}

_check_tool "kubectl"  "kubectl"  "kubectl version --client --short"
_check_tool "helm"     "helm"     "helm version --short"
_check_tool "kind"     "kind"     "kind version"
_check_tool "k3d"      "k3d"      "k3d version"
_check_tool "k9s"      "k9s"      "k9s version --short"
_check_tool "up"       "up"       "up version"
_check_tool "colima"   "colima"   "colima version"

if has_cmd brew && _confirm "Run 'brew upgrade' for installed tools?"; then
  log_info "Running brew upgrade for crossplane-related tools ..."
  for pkg in kind k3d kubernetes-cli helm k9s upbound/tap/up colima; do
    brew upgrade "$pkg" 2>/dev/null && log_ok "$pkg upgraded" || log_info "$pkg already up to date"
  done
fi

# ── Done ───────────────────────────────────────────────────────────────────────
log_section "Update Complete"
log_ok "All selected components have been updated."
echo ""
echo -e "  Verify Crossplane:"
echo -e "    ${CYAN}kubectl get pods -n ${CROSSPLANE_NAMESPACE}${RESET}"
echo -e "    ${CYAN}kubectl get provider${RESET}"
echo ""
