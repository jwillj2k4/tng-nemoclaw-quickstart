#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Prerequisite Installer
# Installs Docker, Node.js, Git, and system dependencies
# Handles native Linux, WSL2, and Docker Desktop environments
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[prereqs]${NC} $1"; }
success() { echo -e "${GREEN}[prereqs]${NC} $1"; }
warn()    { echo -e "${YELLOW}[prereqs]${NC} $1"; }
fail()    { echo -e "${RED}[prereqs]${NC} $1"; exit 1; }

# --- Environment detection --------------------------------------------------
IS_WSL=false
HAS_SYSTEMD=false

detect_environment() {
  if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    IS_WSL=true
    info "WSL2 environment detected."
  fi

  if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    HAS_SYSTEMD=true
  fi
}

# --- Helper: start Docker daemon regardless of init system -------------------
start_docker() {
  # Try systemctl first, then service, then bail with a helpful message
  if [[ "${HAS_SYSTEMD}" == true ]]; then
    sudo systemctl start docker && return 0
  fi
  sudo service docker start 2>/dev/null && return 0

  # Nothing worked
  return 1
}

# --- Git --------------------------------------------------------------------
install_git() {
  if command -v git &> /dev/null; then
    success "Git $(git --version | awk '{print $3}') already installed ✓"
    return
  fi
  info "Installing Git..."
  sudo apt-get update -qq && sudo apt-get install -y -qq git
  success "Git installed ✓"
}

# --- Docker -----------------------------------------------------------------
install_docker() {
  if command -v docker &> /dev/null; then
    success "Docker $(docker --version | awk '{print $3}' | tr -d ',') already installed ✓"

    # Verify Docker daemon is actually reachable
    if docker ps &>/dev/null 2>&1; then
      success "Docker daemon reachable ✓"
    else
      warn "Docker CLI found but daemon not reachable."

      if [[ "${IS_WSL}" == true ]]; then
        warn "WSL2 detected — trying 'sudo service docker start'..."
        if start_docker; then
          sleep 2
          if docker ps &>/dev/null 2>&1; then
            success "Docker started ✓"
            return
          fi
        fi
        echo ""
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn "  Could not start Docker in WSL2. Two options:"
        warn ""
        warn "  Option A — Docker Desktop (recommended):"
        warn "    1. Install/open Docker Desktop for Windows"
        warn "    2. Settings → Resources → WSL Integration"
        warn "    3. Enable integration for your distro"
        warn "    4. Re-run this script"
        warn ""
        warn "  Option B — Native Docker in WSL2:"
        warn "    sudo service docker start"
        warn "    Then re-run this script."
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fail "Docker daemon not reachable. Fix it with one of the options above and retry."
      else
        info "Attempting to start Docker..."
        if start_docker; then
          sleep 2
          if docker ps &>/dev/null 2>&1; then
            success "Docker started ✓"
            return
          fi
        fi
        fail "Could not start Docker. Try 'sudo service docker start' manually."
      fi
    fi

    # Check docker group (non-fatal)
    if ! docker ps &>/dev/null 2>&1 && ! groups 2>/dev/null | grep -q docker; then
      info "Adding current user to docker group..."
      sudo usermod -aG docker "${USER}" 2>/dev/null || true
      warn "You may need to log out/in or run 'newgrp docker'."
    fi
    return
  fi

  # Docker not installed at all
  if [[ "${IS_WSL}" == true ]]; then
    fail "Docker not found. On WSL2, install Docker Desktop for Windows:\n  https://www.docker.com/products/docker-desktop/\n  Then enable WSL integration in Settings → Resources."
  fi

  info "Installing Docker..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
  rm /tmp/get-docker.sh

  start_docker || warn "Could not auto-start Docker."
  sudo usermod -aG docker "${USER}"

  success "Docker installed ✓"
  warn "You may need to log out/in for docker group permissions."
}

# --- Node.js ----------------------------------------------------------------
install_node() {
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    success "Node.js ${NODE_VERSION} already installed ✓"
    return
  fi

  info "Installing Node.js 20 LTS..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
  success "Node.js $(node --version) installed ✓"
}

# --- Build essentials -------------------------------------------------------
install_build_deps() {
  info "Installing build dependencies..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    build-essential \
    curl \
    wget \
    jq \
    ca-certificates \
    gnupg \
    lsb-release
  success "Build dependencies installed ✓"
}

# --- NVIDIA API key check ---------------------------------------------------
check_nvidia_key() {
  if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
    success "NVIDIA API key found in environment ✓"
  elif [[ -f "${HOME}/.nvidia-api-key" ]]; then
    success "NVIDIA API key found at ~/.nvidia-api-key ✓"
  else
    info ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "  No NVIDIA API key detected."
    info ""
    info "  For cloud inference (default profile), you need one."
    info "  Get a free key at: https://build.nvidia.com"
    info ""
    info "  Then either:"
    info "    export NVIDIA_API_KEY='your-key-here'"
    info "    # or"
    info "    echo 'your-key-here' > ~/.nvidia-api-key"
    info ""
    info "  You can skip this if using local vLLM inference only."
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info ""
  fi
}

# --- Main -------------------------------------------------------------------
main() {
  info "Installing prerequisites..."
  detect_environment
  install_build_deps
  install_git
  install_docker
  install_node
  check_nvidia_key
  success "All prerequisites installed."
}

main "$@"
