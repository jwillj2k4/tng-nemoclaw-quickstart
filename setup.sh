#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw Quickstart — Phase 1: Install CLIs + Policies
#
# This script ONLY installs prerequisites and CLIs. It does NOT run
# nemoclaw onboard (which is broken on WSL2 with GPUs).
#
# After this completes, run the platform-specific deploy script:
#   WSL2:  ./scripts/wsl2-deploy.sh nvapi-YOUR-KEY
#   macOS: ./scripts/macos-deploy.sh nvapi-YOUR-KEY
#   Linux: cd ~/.tng-nemoclaw/NemoClaw && nemoclaw onboard
# ============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.tng-nemoclaw"
LOG_FILE="${INSTALL_DIR}/setup.log"

info()    { echo -e "${CYAN}[TNG]${NC} $1"; }
success() { echo -e "${GREEN}[TNG]${NC} $1"; }
warn()    { echo -e "${YELLOW}[TNG]${NC} $1"; }
fail()    { echo -e "${RED}[TNG]${NC} $1"; exit 1; }

# --- Detect platform --------------------------------------------------------
OS_TYPE="linux"
case "$(uname -s)" in
  Darwin) OS_TYPE="macos" ;;
  Linux)
    if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
      OS_TYPE="wsl2"
    fi
    ;;
esac

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════════╗"
  echo "  ║     THE NEW GUARD — NemoClaw Quickstart (Phase 1)       ║"
  echo "  ║     Install CLIs + Security Policy Templates            ║"
  echo "  ╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# --- Preflight --------------------------------------------------------------
preflight() {
  info "Pre-flight checks..."

  # OS
  case "${OS_TYPE}" in
    macos)  success "OS: macOS $(sw_vers -productVersion 2>/dev/null || echo '') ✓" ;;
    wsl2)   success "OS: WSL2 ($(lsb_release -ds 2>/dev/null || echo 'Linux')) ✓" ;;
    linux)
      if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        success "OS: ${PRETTY_NAME:-Linux} ✓"
      fi
      ;;
  esac

  # RAM
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local RAM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024 ))
  else
    local RAM_GB=$(( $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}') / 1024 / 1024 ))
  fi
  if [[ ${RAM_GB} -lt 14 ]]; then
    warn "RAM: ${RAM_GB}GB (16GB+ recommended)"
  else
    success "RAM: ${RAM_GB}GB ✓"
  fi

  # Disk
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local DISK_GB=$(df -g "${HOME}" | tail -1 | awk '{print $4}')
  else
    local DISK_GB=$(df -BG "${HOME}" | tail -1 | awk '{print $4}' | tr -d 'G')
  fi
  if [[ ${DISK_GB} -lt 20 ]]; then
    fail "Disk: ${DISK_GB}GB free (need 20GB+)"
  else
    success "Disk: ${DISK_GB}GB free ✓"
  fi
}

# --- Phase 1a: Prerequisites ------------------------------------------------
install_prereqs() {
  info "Installing prerequisites..."
  bash "${REPO_DIR}/scripts/install-prereqs.sh" 2>&1 | tee -a "${LOG_FILE}"
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    fail "Prerequisites failed. Check ${LOG_FILE}"
  fi
  success "Prerequisites ✓"
}

# --- Phase 1b: Install CLIs ------------------------------------------------
install_clis() {
  info "Installing OpenShell + NemoClaw CLIs..."
  bash "${REPO_DIR}/scripts/deploy-nemoclaw.sh" 2>&1 | tee -a "${LOG_FILE}"
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    warn "CLI install had issues. Check output above."
  fi
  success "CLIs ✓"
}

# --- Phase 1c: Copy policies -----------------------------------------------
install_policies() {
  info "Deploying TNG security policies..."
  local POLICY_DEST="${INSTALL_DIR}/policies"
  mkdir -p "${POLICY_DEST}"
  cp -r "${REPO_DIR}/policies/"* "${POLICY_DEST}/"
  success "Policy templates → ${POLICY_DEST} ✓"
}

# --- Summary ----------------------------------------------------------------
print_next_steps() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════════╗"
  echo "  ║               PHASE 1 COMPLETE — CLIs Installed          ║"
  echo "  ╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  case "${OS_TYPE}" in
    wsl2)
      echo -e "  ${BOLD}Next step (WSL2):${NC}"
      echo "    ./scripts/wsl2-deploy.sh nvapi-YOUR-NVIDIA-KEY"
      echo ""
      echo "  Get a free key at: https://build.nvidia.com"
      ;;
    macos)
      echo -e "  ${BOLD}Next step (macOS):${NC}"
      echo "    ./scripts/macos-deploy.sh nvapi-YOUR-NVIDIA-KEY"
      echo ""
      echo "  Get a free key at: https://build.nvidia.com"
      ;;
    linux)
      echo -e "  ${BOLD}Next step (Linux):${NC}"
      echo "    cd ~/.tng-nemoclaw/NemoClaw && nemoclaw onboard"
      echo ""
      echo "  If you have an NVIDIA GPU and onboard fails with sandbox errors,"
      echo "  use the WSL2 workaround instead:"
      echo "    ./scripts/wsl2-deploy.sh nvapi-YOUR-NVIDIA-KEY"
      ;;
  esac

  echo ""
  echo -e "  ${BOLD}Policies:${NC}   ${INSTALL_DIR}/policies/"
  echo -e "  ${BOLD}Logs:${NC}       ${LOG_FILE}"
  echo -e "  ${BOLD}Docs:${NC}       ${REPO_DIR}/docs/"
  echo -e "  ${BOLD}Teardown:${NC}   bash ${REPO_DIR}/scripts/teardown.sh"
  echo ""
  echo -e "  ${CYAN}Built by The New Guard — thenewguard.ai${NC}"
  echo ""
}

# --- Main -------------------------------------------------------------------
main() {
  banner
  mkdir -p "${INSTALL_DIR}"
  echo "=== TNG Setup Phase 1 — $(date) ===" > "${LOG_FILE}"

  preflight
  install_prereqs
  install_clis
  install_policies
  print_next_steps
}

main "$@"
