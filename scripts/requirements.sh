#!/usr/bin/env bash
# scripts/requirements.sh — display and validate system requirements

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── Minimum requirements ──────────────────────────────────────────────────────
MIN_RAM_GIB=8
REC_RAM_GIB=16
MIN_CPU=4
MIN_DISK_GIB=20
REC_DISK_GIB=40

# ── Display requirements table ────────────────────────────────────────────────
show_requirements() {
  local os="$1"
  log_section "System Requirements"

  echo -e "  The following resources are needed to run Crossplane locally:\n"
  printf "  %-22s %-15s %-15s\n" "Resource" "Minimum" "Recommended"
  printf "  %-22s %-15s %-15s\n" "--------" "-------" "-----------"
  printf "  %-22s %-15s %-15s\n" "RAM"     "${MIN_RAM_GIB} GiB"   "${REC_RAM_GIB} GiB"
  printf "  %-22s %-15s %-15s\n" "CPU cores" "${MIN_CPU}"         "6+"
  printf "  %-22s %-15s %-15s\n" "Free disk space" "${MIN_DISK_GIB} GiB" "${REC_DISK_GIB} GiB"
  echo ""

  echo -e "  Required software (will be installed automatically if missing):\n"
  echo -e "    • Docker Desktop / Docker Engine (${BOLD}must be installed & running${RESET})"
  echo -e "    • kind    — Kubernetes in Docker"
  echo -e "    • kubectl — Kubernetes CLI"
  echo -e "    • helm    — Kubernetes package manager"
  echo -e "    • up      — Crossplane CLI\n"

  case "$os" in
    macos)
      echo -e "  ${YELLOW}macOS notes:${RESET}"
      echo -e "    • Docker Desktop must have at least ${MIN_RAM_GIB} GiB memory allocated"
      echo -e "      (Docker Desktop → Settings → Resources → Memory)"
      echo -e "    • homebrew is used to install missing tools\n"
      ;;
    linux)
      echo -e "  ${YELLOW}Linux notes:${RESET}"
      echo -e "    • apt (Debian/Ubuntu) or yum/dnf (RHEL/Fedora) will be used"
      echo -e "    • sudo privileges required for package installation\n"
      ;;
    windows)
      echo -e "  ${YELLOW}Windows notes:${RESET}"
      echo -e "    • WSL 2 must be enabled"
      echo -e "    • Docker Desktop with WSL 2 backend is required"
      echo -e "    • winget / Chocolatey / Scoop used for package installation\n"
      ;;
  esac
}

# ── Check actual system resources ─────────────────────────────────────────────
check_system_resources() {
  local os="$1"
  local all_ok=true

  log_section "Checking System Resources"

  # ── RAM ──
  local ram_gib=0
  case "$os" in
    macos)
      local ram_bytes
      ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
      ram_gib=$(bytes_to_gib "$ram_bytes")
      ;;
    linux)
      ram_gib=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
      ;;
  esac

  if (( ram_gib >= REC_RAM_GIB )); then
    log_ok "RAM: ${ram_gib} GiB (recommended: ${REC_RAM_GIB} GiB)"
  elif (( ram_gib >= MIN_RAM_GIB )); then
    log_warn "RAM: ${ram_gib} GiB — meets minimum (${MIN_RAM_GIB} GiB), recommended ${REC_RAM_GIB} GiB"
  else
    log_error "RAM: ${ram_gib} GiB — below minimum (${MIN_RAM_GIB} GiB required)"
    all_ok=false
  fi

  # ── CPU ──
  local cpu_cores=0
  case "$os" in
    macos) cpu_cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 0) ;;
    linux) cpu_cores=$(nproc 2>/dev/null || echo 0) ;;
  esac

  if (( cpu_cores >= MIN_CPU )); then
    log_ok "CPU: ${cpu_cores} cores (minimum: ${MIN_CPU})"
  else
    log_error "CPU: ${cpu_cores} cores — below minimum (${MIN_CPU} required)"
    all_ok=false
  fi

  # ── Disk ──
  local disk_gib=0
  disk_gib=$(df -BG . 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 0)

  if (( disk_gib >= REC_DISK_GIB )); then
    log_ok "Free disk: ${disk_gib} GiB (recommended: ${REC_DISK_GIB} GiB)"
  elif (( disk_gib >= MIN_DISK_GIB )); then
    log_warn "Free disk: ${disk_gib} GiB — meets minimum (${MIN_DISK_GIB} GiB), recommended ${REC_DISK_GIB} GiB"
  else
    log_error "Free disk: ${disk_gib} GiB — below minimum (${MIN_DISK_GIB} GiB required)"
    all_ok=false
  fi

  # ── Docker ──
  if has_cmd docker; then
    if docker info &>/dev/null 2>&1; then
      log_ok "Docker: running ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
    else
      log_error "Docker is installed but not running — please start Docker and re-run."
      all_ok=false
    fi
  else
    log_error "Docker not found — please install Docker Desktop first."
    echo -e "         macOS/Windows: https://www.docker.com/products/docker-desktop"
    echo -e "         Linux:         https://docs.docker.com/engine/install/"
    all_ok=false
  fi

  echo ""
  if [[ "$all_ok" == false ]]; then
    log_error "One or more requirements are not met. Please fix the issues above and re-run."
    return 1
  fi

  log_ok "All resource checks passed."
  return 0
}
