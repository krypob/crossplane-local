#!/usr/bin/env bash
# scripts/requirements.sh — display and validate system requirements

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── Requirement tiers ─────────────────────────────────────────────────────────
#   standard    = Docker Desktop + kind  (full Kubernetes)
#   lightweight = Colima + k3d           (k3s, ~70% less RAM/CPU)

STD_MIN_RAM=8;  STD_REC_RAM=16; STD_MIN_CPU=4; STD_REC_CPU=6;  STD_MIN_DISK=20; STD_REC_DISK=40
LW_MIN_RAM=2;   LW_REC_RAM=4;   LW_MIN_CPU=2;  LW_REC_CPU=4;   LW_MIN_DISK=8;   LW_REC_DISK=20

_req() {
  # _req <stack> <field>   e.g.  _req lightweight min_ram
  local stack="$1" field="$2"
  case "${stack}_${field}" in
    standard_min_ram)  echo $STD_MIN_RAM ;;
    standard_rec_ram)  echo $STD_REC_RAM ;;
    standard_min_cpu)  echo $STD_MIN_CPU ;;
    standard_rec_cpu)  echo $STD_REC_CPU ;;
    standard_min_disk) echo $STD_MIN_DISK ;;
    standard_rec_disk) echo $STD_REC_DISK ;;
    lightweight_min_ram)  echo $LW_MIN_RAM ;;
    lightweight_rec_ram)  echo $LW_REC_RAM ;;
    lightweight_min_cpu)  echo $LW_MIN_CPU ;;
    lightweight_rec_cpu)  echo $LW_REC_CPU ;;
    lightweight_min_disk) echo $LW_MIN_DISK ;;
    lightweight_rec_disk) echo $LW_REC_DISK ;;
  esac
}

# ── Display requirements table ────────────────────────────────────────────────
show_requirements() {
  local os="$1"
  local stack="${2:-standard}"

  log_section "System Requirements"

  if [[ "$stack" == "lightweight" ]]; then
    echo -e "  Stack: ${BOLD}${GREEN}Lightweight${RESET} — Colima + k3d/k3s (low resource usage)\n"
  else
    echo -e "  Stack: ${BOLD}Standard${RESET} — Docker + kind (full Kubernetes)\n"
  fi

  printf "  %-22s %-15s %-15s\n" "Resource" "Minimum" "Recommended"
  printf "  %-22s %-15s %-15s\n" "--------" "-------" "-----------"
  printf "  %-22s %-15s %-15s\n" "RAM"       "$(_req "$stack" min_ram) GiB"  "$(_req "$stack" rec_ram) GiB"
  printf "  %-22s %-15s %-15s\n" "CPU cores" "$(_req "$stack" min_cpu)"       "$(_req "$stack" rec_cpu)+"
  printf "  %-22s %-15s %-15s\n" "Free disk" "$(_req "$stack" min_disk) GiB" "$(_req "$stack" rec_disk) GiB"
  echo ""

  echo -e "  Software (auto-installed if missing):\n"
  if [[ "$stack" == "lightweight" ]]; then
    echo -e "    • Colima    — lightweight container runtime (replaces Docker Desktop)"
    echo -e "    • k3d       — k3s Kubernetes cluster inside containers"
  else
    echo -e "    • Docker Desktop / Docker Engine ${BOLD}(must be installed & running)${RESET}"
    echo -e "    • kind      — Kubernetes in Docker"
  fi
  echo -e "    • kubectl   — Kubernetes CLI"
  echo -e "    • helm      — Kubernetes package manager"
  echo -e "    • up        — Crossplane CLI"
  echo ""

  case "$os" in
    macos)
      echo -e "  ${YELLOW}macOS notes:${RESET}"
      if [[ "$stack" == "lightweight" ]]; then
        echo -e "    • Colima runs a Lima VM in the background — no GUI needed"
        echo -e "    • homebrew is used to install all tools"
      else
        echo -e "    • Docker Desktop → Settings → Resources → Memory >= $(_req "$stack" min_ram) GiB"
        echo -e "    • homebrew is used to install all tools"
      fi
      echo ""
      ;;
    linux)
      echo -e "  ${YELLOW}Linux notes:${RESET}"
      echo -e "    • sudo privileges required for package installation"
      echo ""
      ;;
  esac
}

# ── Check actual system resources ─────────────────────────────────────────────
# NOTE: failures are soft — they warn but always allow the user to continue.
check_system_resources() {
  local os="$1"
  local stack="${2:-standard}"

  local min_ram min_cpu min_disk
  min_ram=$(_req "$stack" min_ram)
  min_cpu=$(_req "$stack" min_cpu)
  min_disk=$(_req "$stack" min_disk)

  log_section "Checking System Resources"

  local warnings=0

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

  local rec_ram; rec_ram=$(_req "$stack" rec_ram)
  if (( ram_gib >= rec_ram )); then
    log_ok "RAM: ${ram_gib} GiB"
  elif (( ram_gib >= min_ram )); then
    log_warn "RAM: ${ram_gib} GiB — meets minimum, recommended ${rec_ram} GiB"
  else
    log_warn "RAM: ${ram_gib} GiB — below minimum (${min_ram} GiB). Performance may be degraded."
    (( warnings++ )) || true
  fi

  # ── CPU ──
  local cpu_cores=0
  case "$os" in
    macos) cpu_cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 0) ;;
    linux) cpu_cores=$(nproc 2>/dev/null || echo 0) ;;
  esac

  if (( cpu_cores >= min_cpu )); then
    log_ok "CPU: ${cpu_cores} cores"
  else
    log_warn "CPU: ${cpu_cores} cores — below minimum (${min_cpu}). Setup may be slow."
    (( warnings++ )) || true
  fi

  # ── Disk ──
  local disk_gib=0
  case "$os" in
    macos) disk_gib=$(df -g . 2>/dev/null | awk 'NR==2 {print $4}' || echo 0) ;;
    linux) disk_gib=$(df -BG . 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 0) ;;
  esac

  local rec_disk; rec_disk=$(_req "$stack" rec_disk)
  if (( disk_gib >= rec_disk )); then
    log_ok "Free disk: ${disk_gib} GiB"
  elif (( disk_gib >= min_disk )); then
    log_warn "Free disk: ${disk_gib} GiB — meets minimum, recommended ${rec_disk} GiB"
  else
    log_warn "Free disk: ${disk_gib} GiB — below minimum (${min_disk} GiB). Images may not fit."
    (( warnings++ )) || true
  fi

  # ── Runtime check ──
  if [[ "$stack" == "lightweight" ]]; then
    log_info "Colima will be installed and started automatically in the next step."
  else
    if has_cmd docker; then
      if docker info &>/dev/null 2>&1; then
        log_ok "Docker: running ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
      else
        log_warn "Docker installed but not running — start Docker Desktop before continuing."
        (( warnings++ )) || true
      fi
    else
      log_warn "Docker not found. Install Docker Desktop first or choose the Lightweight stack."
      (( warnings++ )) || true
    fi
  fi

  echo ""

  if (( warnings > 0 )); then
    echo -e "  ${YELLOW}${warnings} check(s) below minimum.${RESET} You can still proceed — results may vary.\n"
    if ! ask_yes_no "Continue anyway?"; then
      log_warn "Setup cancelled."
      exit 1
    fi
  else
    log_ok "All resource checks passed."
  fi

  return 0
}
