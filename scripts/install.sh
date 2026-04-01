#!/usr/bin/env bash
# scripts/install.sh — install missing tools (kubectl, helm, kind, crossplane CLI)

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── Version pins (override via env if needed) ─────────────────────────────────
KIND_VERSION="${KIND_VERSION:-v0.25.0}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.31.0}"
HELM_VERSION="${HELM_VERSION:-v3.16.2}"
UP_VERSION="${UP_VERSION:-v0.33.0}"   # Crossplane CLI (up)

# ── macOS ─────────────────────────────────────────────────────────────────────
install_tools_macos() {
  log_section "Installing Tools (macOS)"

  if ! has_cmd brew; then
    log_error "Homebrew not found. Install it first: https://brew.sh"
    exit 1
  fi

  _install_brew_pkg "kind"    "kind"    "kind"
  _install_brew_pkg "kubectl" "kubectl" "kubernetes-cli"
  _install_brew_pkg "helm"    "helm"    "helm"

  # Crossplane CLI (up) — via direct binary or brew tap
  if ! has_cmd up; then
    log_info "Installing Crossplane CLI (up) ..."
    if brew tap upbound/tap &>/dev/null && brew install upbound/tap/up; then
      log_ok "up installed via Homebrew"
    else
      _install_up_binary "darwin" "$(uname -m)"
    fi
  else
    log_ok "up $(up version 2>/dev/null | head -1) already installed"
  fi
}

_install_brew_pkg() {
  local name="$1" cmd="$2" pkg="$3"
  if has_cmd "$cmd"; then
    log_ok "${name} already installed ($(${cmd} version --client --short 2>/dev/null || ${cmd} version 2>/dev/null | head -1))"
  else
    log_info "Installing ${name} via Homebrew ..."
    brew install "$pkg" && log_ok "${name} installed" || { log_error "Failed to install ${name}"; exit 1; }
  fi
}

# ── Linux ─────────────────────────────────────────────────────────────────────
install_tools_linux() {
  log_section "Installing Tools (Linux)"

  _install_kind_linux
  _install_kubectl_linux
  _install_helm_linux
  _install_up_binary "linux" "$(uname -m)"
}

_install_kind_linux() {
  if has_cmd kind; then
    log_ok "kind $(kind version) already installed"
    return
  fi
  log_info "Installing kind ${KIND_VERSION} ..."
  local arch
  arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  local url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${arch}"
  curl -fsSLo /tmp/kind "$url"
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
  log_ok "kind installed"
}

_install_kubectl_linux() {
  if has_cmd kubectl; then
    log_ok "kubectl $(kubectl version --client --short 2>/dev/null) already installed"
    return
  fi
  log_info "Installing kubectl ${KUBECTL_VERSION} ..."
  local arch
  arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  curl -fsSLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
  log_ok "kubectl installed"
}

_install_helm_linux() {
  if has_cmd helm; then
    log_ok "helm $(helm version --short) already installed"
    return
  fi
  log_info "Installing helm ${HELM_VERSION} ..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_ok "helm installed"
}

_install_up_binary() {
  local os="$1" arch="$2"
  arch=$(echo "$arch" | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  local os_name="$os"
  [[ "$os" == "darwin" ]] && os_name="darwin"

  if has_cmd up; then
    log_ok "up $(up version 2>/dev/null | head -1) already installed"
    return
  fi

  log_info "Installing Crossplane CLI (up) ${UP_VERSION} ..."
  local url="https://cli.upbound.io/stable/${UP_VERSION}/bin/${os_name}_${arch}/up"
  if curl -fsSLo /tmp/up "$url"; then
    chmod +x /tmp/up
    sudo mv /tmp/up /usr/local/bin/up
    log_ok "up installed"
  else
    log_warn "Could not download Crossplane CLI (up). Skipping — crossplane will still work via helm."
  fi
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
install_tools() {
  local os="$1"
  case "$os" in
    macos) install_tools_macos ;;
    linux) install_tools_linux ;;
    *)
      log_error "install.sh: unsupported OS '$os'"
      exit 1
      ;;
  esac
}
