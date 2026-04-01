#!/usr/bin/env bash
# scripts/common.sh — shared colors, logging, and utility functions

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
                echo -e "${BOLD}${CYAN}  $*${RESET}"; \
                echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Print a banner
print_banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'EOF'
   ____                                  _
  / ___|_ __ ___  ___ ___ _ __ ___  ___| | __ _ _ __   ___
 | |   | '__/ _ \/ __/ __| '_ ` _ \/ __| |/ _` | '_ \ / _ \
 | |___| | | (_) \__ \__ \ |_) | | | (__| | (_| | | | |  __/
  \____|_|  \___/|___/___/ .__/|_|_|\___|_|\__,_|_| |_|\___|
                          |_|
         Local Environment Setup — powered by kind + helm
EOF
  echo -e "${RESET}"
}

# Ask yes/no question; returns 0 for yes, 1 for no
ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"   # 'y' or 'n'
  local options
  [[ "$default" == "y" ]] && options="[Y/n]" || options="[y/N]"

  while true; do
    read -rp "$(echo -e "${YELLOW}${prompt} ${options}: ${RESET}")" answer
    answer="${answer:-$default}"
    answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "Please answer y or n." ;;
    esac
  done
}

# Require a command; exit if not present
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Required command '$1' not found. $2"
    exit 1
  fi
}

# Check if a command exists (no exit)
has_cmd() { command -v "$1" &>/dev/null; }

# Print bytes as human-readable GiB
bytes_to_gib() { echo $(( $1 / 1024 / 1024 / 1024 )); }
