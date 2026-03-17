#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Prerequisite Installer (macOS / Linux / WSL2)
# ============================================================================

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${CYAN}[prereqs]${NC} $1"; }
success() { echo -e "${GREEN}[prereqs]${NC} $1"; }
warn()    { echo -e "${YELLOW}[prereqs]${NC} $1"; }
fail()    { echo -e "${RED}[prereqs]${NC} $1"; exit 1; }

OS_TYPE="linux"
case "$(uname -s)" in
  Darwin) OS_TYPE="macos" ;;
  Linux) grep -qi "microsoft\|wsl" /proc/version 2>/dev/null && OS_TYPE="wsl2" ;;
esac

# --- Git --------------------------------------------------------------------
if command -v git &>/dev/null; then
  success "Git $(git --version | awk '{print $3}') ✓"
else
  case "${OS_TYPE}" in
    macos) command -v brew &>/dev/null && brew install git || xcode-select --install ;;
    *) sudo apt-get update -qq && sudo apt-get install -y -qq git ;;
  esac
fi

# --- Docker -----------------------------------------------------------------
if command -v docker &>/dev/null; then
  success "Docker $(docker --version | awk '{print $3}' | tr -d ',') ✓"
  if docker ps &>/dev/null 2>&1; then
    success "Docker daemon reachable ✓"
  else
    case "${OS_TYPE}" in
      macos) fail "Docker Desktop not running. Open Docker Desktop and retry." ;;
      wsl2)
        sudo service docker start 2>/dev/null && sleep 2
        docker ps &>/dev/null 2>&1 && success "Docker started ✓" || \
          fail "Docker not reachable. Start Docker Desktop or run: sudo service docker start"
        ;;
      *) sudo service docker start 2>/dev/null || sudo systemctl start docker 2>/dev/null ;;
    esac
  fi
else
  case "${OS_TYPE}" in
    macos) fail "Install Docker Desktop for Mac: https://www.docker.com/products/docker-desktop/" ;;
    wsl2) fail "Install Docker Desktop for Windows + enable WSL integration" ;;
    *) curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker "${USER}" ;;
  esac
fi

# --- Node.js ----------------------------------------------------------------
if command -v node &>/dev/null; then
  success "Node.js $(node --version) ✓"
else
  case "${OS_TYPE}" in
    macos) command -v brew &>/dev/null && brew install node@20 || fail "Install Homebrew then: brew install node@20" ;;
    *) curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y -qq nodejs ;;
  esac
fi

# --- Build deps (Linux/WSL2 only) ------------------------------------------
if [[ "${OS_TYPE}" != "macos" ]]; then
  sudo apt-get update -qq && sudo apt-get install -y -qq build-essential curl wget jq ca-certificates gnupg lsb-release 2>/dev/null
  success "Build dependencies ✓"
else
  command -v jq &>/dev/null || (command -v brew &>/dev/null && brew install jq)
  success "macOS dependencies ✓"
fi

success "All prerequisites installed."
