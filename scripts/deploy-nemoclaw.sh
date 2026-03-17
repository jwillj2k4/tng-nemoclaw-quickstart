#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Install OpenShell + NemoClaw CLIs
# This ONLY installs the CLIs. Deployment is handled by platform scripts.
# ============================================================================

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.tng-nemoclaw"

info()    { echo -e "${CYAN}[deploy]${NC} $1"; }
success() { echo -e "${GREEN}[deploy]${NC} $1"; }
warn()    { echo -e "${YELLOW}[deploy]${NC} $1"; }

mkdir -p "${INSTALL_DIR}"

# --- OpenShell --------------------------------------------------------------
OPENSHELL_DIR="${INSTALL_DIR}/OpenShell"
if [[ -d "${OPENSHELL_DIR}" ]]; then
  cd "${OPENSHELL_DIR}" && git pull --ff-only 2>/dev/null || true
else
  git clone https://github.com/NVIDIA/OpenShell.git "${OPENSHELL_DIR}"
fi

cd "${OPENSHELL_DIR}"
if [[ -f "install.sh" ]]; then
  chmod +x install.sh && bash install.sh
fi

# Ensure PATH
if ! command -v openshell &>/dev/null && [[ -f "${HOME}/.local/bin/openshell" ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
fi
command -v openshell &>/dev/null && success "openshell CLI ✓" || warn "openshell not in PATH — add ~/.local/bin"

# --- NemoClaw ---------------------------------------------------------------
NEMOCLAW_DIR="${INSTALL_DIR}/NemoClaw"
if [[ -d "${NEMOCLAW_DIR}" ]]; then
  cd "${NEMOCLAW_DIR}" && git pull --ff-only 2>/dev/null || true
else
  git clone https://github.com/NVIDIA/NemoClaw.git "${NEMOCLAW_DIR}"
fi

cd "${NEMOCLAW_DIR}"
npm install 2>&1 | tail -3
npm link 2>&1 || sudo npm link 2>&1 || true

command -v nemoclaw &>/dev/null && success "nemoclaw CLI ✓" || warn "nemoclaw not in PATH — try: npm link"

success "CLI installation complete."
