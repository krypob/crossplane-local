#!/usr/bin/env bash
# scripts/install.sh — install missing tools (kubectl, helm, kind/k3d, colima, crossplane CLI)

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── Version pins (override via env if needed) ─────────────────────────────────
KIND_VERSION="${KIND_VERSION:-v0.25.0}"
K3D_VERSION="${K3D_VERSION:-v5.7.4}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.31.0}"
HELM_VERSION="${HELM_VERSION:-v3.16.2}"
UP_VERSION="${UP_VERSION:-v0.33.0}"
COLIMA_CPU="${COLIMA_CPU:-2}"
COLIMA_MEMORY="${COLIMA_MEMORY:-4}"   # GiB
COLIMA_DISK="${COLIMA_DISK:-60}"      # GiB

# ── macOS — standard stack (Docker + kind) ────────────────────────────────────
install_tools_macos_standard() {
  log_section "Installing Tools — macOS / Standard (Docker + kind)"
  _require_brew
  _brew_install "kind"    "kind"    "kind"
  _brew_install "kubectl" "kubectl" "kubernetes-cli"
  _brew_install "helm"    "helm"    "helm"
  _install_up_brew
  _install_k9s_brew
}

# ── macOS — lightweight stack (Colima + k3d) ──────────────────────────────────
install_tools_macos_lightweight() {
  log_section "Installing Tools — macOS / Lightweight (Colima + k3d)"
  _require_brew
  _install_k9s_brew

  # Colima
  if has_cmd colima; then
    log_ok "colima $(colima version 2>/dev/null | head -1) already installed"
  else
    log_info "Installing Colima ..."
    brew install colima && log_ok "Colima installed"
  fi

  # Docker CLI (needed by k3d even when using Colima)
  if has_cmd docker; then
    log_ok "docker CLI already installed"
  else
    log_info "Installing docker CLI ..."
    brew install docker && log_ok "docker CLI installed"
  fi

  # k3d
  if has_cmd k3d; then
    log_ok "k3d $(k3d version 2>/dev/null | head -1) already installed"
  else
    log_info "Installing k3d ..."
    brew install k3d && log_ok "k3d installed"
  fi

  _brew_install "kubectl" "kubectl" "kubernetes-cli"
  _brew_install "helm"    "helm"    "helm"
  _install_up_brew

  # Start Colima if not running
  _ensure_colima_running
}

_ensure_colima_running() {
  if colima status 2>/dev/null | grep -q "Running"; then
    log_ok "Colima is running"
    return
  fi
  log_info "Starting Colima (cpu=${COLIMA_CPU}, memory=${COLIMA_MEMORY}GiB, disk=${COLIMA_DISK}GiB) ..."
  colima start \
    --cpu "${COLIMA_CPU}" \
    --memory "${COLIMA_MEMORY}" \
    --disk "${COLIMA_DISK}" \
    --runtime docker
  log_ok "Colima started"
}

# ── Linux — standard stack ────────────────────────────────────────────────────
install_tools_linux_standard() {
  log_section "Installing Tools — Linux / Standard (Docker + kind)"
  _install_kind_linux
  _install_kubectl_linux
  _install_helm_linux
  _install_up_binary "linux" "$(uname -m)"
  _install_k9s_linux
}

# ── Linux — lightweight stack ─────────────────────────────────────────────────
install_tools_linux_lightweight() {
  log_section "Installing Tools — Linux / Lightweight (k3d)"
  # On Linux, Docker Engine is much lighter than Docker Desktop
  # k3d runs k3s which uses far less memory than full k8s
  if ! has_cmd docker || ! docker info &>/dev/null 2>&1; then
    log_info "Installing Docker Engine (lightweight daemon, no Desktop UI) ..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "${USER}" || true
    log_ok "Docker Engine installed"
    log_warn "You may need to re-login for docker group membership to take effect."
    log_warn "If the next step fails, run: newgrp docker"
  else
    log_ok "Docker already running"
  fi
  _install_k3d_linux
  _install_kubectl_linux
  _install_helm_linux
  _install_up_binary "linux" "$(uname -m)"
  _install_k9s_linux
}

# ── Shared brew helper ────────────────────────────────────────────────────────
_require_brew() {
  if ! has_cmd brew; then
    log_error "Homebrew not found. Install it first: https://brew.sh"
    exit 1
  fi
}

_brew_install() {
  local name="$1" cmd="$2" pkg="$3"
  if has_cmd "$cmd"; then
    log_ok "${name} already installed"
  else
    log_info "Installing ${name} via Homebrew ..."
    brew install "$pkg" && log_ok "${name} installed" || { log_error "Failed to install ${name}"; exit 1; }
  fi
}

_install_up_brew() {
  if has_cmd up; then
    log_ok "up (Crossplane CLI) already installed"
    return
  fi
  log_info "Installing Crossplane CLI (up) via Homebrew ..."
  if brew tap upbound/tap &>/dev/null && brew install upbound/tap/up; then
    log_ok "up installed"
  else
    _install_up_binary "darwin" "$(uname -m)"
  fi
}

# ── Shared binary installers ──────────────────────────────────────────────────
_install_kind_linux() {
  has_cmd kind && { log_ok "kind already installed"; return; }
  log_info "Installing kind ${KIND_VERSION} ..."
  local arch; arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${arch}"
  chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind
  log_ok "kind installed"
}

_install_k3d_linux() {
  has_cmd k3d && { log_ok "k3d already installed"; return; }
  log_info "Installing k3d ${K3D_VERSION} ..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG="${K3D_VERSION}" bash
  log_ok "k3d installed"
}

_install_kubectl_linux() {
  has_cmd kubectl && { log_ok "kubectl already installed"; return; }
  log_info "Installing kubectl ${KUBECTL_VERSION} ..."
  local arch; arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  curl -fsSLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
  chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
  log_ok "kubectl installed"
}

_install_helm_linux() {
  has_cmd helm && { log_ok "helm already installed"; return; }
  log_info "Installing helm ..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_ok "helm installed"
}

_install_up_binary() {
  has_cmd up && { log_ok "up (Crossplane CLI) already installed"; return; }
  local os="$1" arch="$2"
  arch=$(echo "$arch" | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  local os_name="$os"; [[ "$os" == "darwin" ]] && os_name="darwin"
  log_info "Installing Crossplane CLI (up) ${UP_VERSION} ..."
  local url="https://cli.upbound.io/stable/${UP_VERSION}/bin/${os_name}_${arch}/up"
  if curl -fsSLo /tmp/up "$url"; then
    chmod +x /tmp/up && sudo mv /tmp/up /usr/local/bin/up
    log_ok "up installed"
  else
    log_warn "Could not download Crossplane CLI (up). Crossplane will still work via helm."
  fi
}

# ── k9s installers ────────────────────────────────────────────────────────────
K9S_VERSION="${K9S_VERSION:-v0.32.7}"

_install_k9s_brew() {
  if has_cmd k9s; then
    log_ok "k9s $(k9s version --short 2>/dev/null | head -1) already installed"
    return
  fi
  log_info "Installing k9s (terminal UI for Kubernetes) ..."
  brew install derailed/k9s/k9s && log_ok "k9s installed" || { log_error "Failed to install k9s"; exit 1; }
}

_install_k9s_linux() {
  if has_cmd k9s; then
    log_ok "k9s $(k9s version --short 2>/dev/null | head -1) already installed"
    return
  fi
  log_info "Installing k9s ${K9S_VERSION} ..."
  local arch; arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  local url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${arch}.tar.gz"
  curl -fsSL "$url" | tar -xzf - -C /tmp k9s
  sudo mv /tmp/k9s /usr/local/bin/k9s
  log_ok "k9s installed"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
install_tools() {
  local os="$1"
  local stack="${2:-standard}"
  case "${os}_${stack}" in
    macos_standard)    install_tools_macos_standard ;;
    macos_lightweight) install_tools_macos_lightweight ;;
    linux_standard)    install_tools_linux_standard ;;
    linux_lightweight) install_tools_linux_lightweight ;;
    *)
      log_error "install.sh: unsupported combination os='${os}' stack='${stack}'"
      exit 1
      ;;
  esac
}
