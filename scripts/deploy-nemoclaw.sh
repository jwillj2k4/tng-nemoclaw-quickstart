#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Deploy NemoClaw + OpenShell
# Clones repos, builds OpenShell, runs NemoClaw installer
# Handles cgroup v2 / Docker cgroupns issues (common on WSL2 and modern Linux)
# ============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.tng-nemoclaw"

info()    { echo -e "${CYAN}[deploy]${NC} $1"; }
success() { echo -e "${GREEN}[deploy]${NC} $1"; }
warn()    { echo -e "${YELLOW}[deploy]${NC} $1"; }
fail()    { echo -e "${RED}[deploy]${NC} $1"; exit 1; }

# --- Detect environment -----------------------------------------------------
IS_WSL=false
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
  IS_WSL=true
fi

# --- Fix cgroup v2 for Docker (required by OpenShell/k3s) -------------------
fix_cgroup_v2() {
  # OpenShell's gateway runs k3s inside Docker, which needs cgroupns=host.
  # Without this, you get: "openat2 /sys/fs/cgroup/kubepods/pids.max: no such file or directory"
  # NemoClaw's own fix is `nemoclaw setup-spark`, but we handle it proactively.

  local DAEMON_JSON="/etc/docker/daemon.json"

  # Check if cgroup v2 is in use
  if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
    info "cgroup v1 detected — no fix needed."
    return
  fi

  info "cgroup v2 detected — checking Docker cgroupns config..."

  # Check if already configured
  if [[ -f "${DAEMON_JSON}" ]]; then
    if grep -q '"default-cgroupns-mode"' "${DAEMON_JSON}" 2>/dev/null; then
      local CURRENT=$(jq -r '.["default-cgroupns-mode"] // empty' "${DAEMON_JSON}" 2>/dev/null || true)
      if [[ "${CURRENT}" == "host" ]]; then
        success "Docker cgroupns=host already configured ✓"
        return
      fi
    fi
  fi

  info "Configuring Docker for cgroupns=host (required by OpenShell/k3s)..."

  # Build or update daemon.json
  if [[ -f "${DAEMON_JSON}" ]]; then
    # Merge into existing config
    local EXISTING
    EXISTING=$(cat "${DAEMON_JSON}" 2>/dev/null || echo "{}")
    if ! echo "${EXISTING}" | jq . &>/dev/null; then
      warn "Existing ${DAEMON_JSON} is not valid JSON. Backing up and replacing."
      sudo cp "${DAEMON_JSON}" "${DAEMON_JSON}.bak.$(date +%s)"
      EXISTING="{}"
    fi
    echo "${EXISTING}" | jq '. + {"default-cgroupns-mode": "host"}' | sudo tee "${DAEMON_JSON}" > /dev/null
  else
    # Create new
    echo '{"default-cgroupns-mode": "host"}' | sudo tee "${DAEMON_JSON}" > /dev/null
  fi

  # Restart Docker to pick up the change
  info "Restarting Docker to apply cgroup config..."
  if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    sudo systemctl restart docker
  else
    sudo service docker restart 2>/dev/null || true
  fi

  # Wait for Docker to come back
  local RETRIES=0
  while ! docker ps &>/dev/null 2>&1; do
    ((RETRIES++))
    if [[ ${RETRIES} -gt 15 ]]; then
      fail "Docker didn't come back after cgroup config change. Check 'sudo service docker status'."
    fi
    sleep 2
  done

  success "Docker restarted with cgroupns=host ✓"
}

# --- Clone OpenShell --------------------------------------------------------
clone_openshell() {
  OPENSHELL_DIR="${INSTALL_DIR}/OpenShell"

  if [[ -d "${OPENSHELL_DIR}" ]]; then
    info "OpenShell directory exists. Pulling latest..."
    cd "${OPENSHELL_DIR}" && git pull --ff-only 2>/dev/null || warn "Git pull failed — using existing checkout."
  else
    info "Cloning NVIDIA OpenShell..."
    git clone https://github.com/NVIDIA/OpenShell.git "${OPENSHELL_DIR}"
  fi

  success "OpenShell source ready ✓"
}

# --- Install OpenShell ------------------------------------------------------
install_openshell() {
  OPENSHELL_DIR="${INSTALL_DIR}/OpenShell"
  cd "${OPENSHELL_DIR}"

  info "Installing OpenShell..."

  # OpenShell ships an install.sh that downloads the correct binary
  if [[ -f "install.sh" ]]; then
    chmod +x install.sh
    bash install.sh
  elif [[ -f "Makefile" ]]; then
    make build
  else
    warn "No standard install method found. Checking if openshell is already in PATH..."
  fi

  # Verify
  if command -v openshell &>/dev/null; then
    success "OpenShell $(openshell --version 2>/dev/null || echo 'installed') ✓"
  elif [[ -f "${HOME}/.local/bin/openshell" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
    success "OpenShell installed to ~/.local/bin ✓"
  else
    warn "openshell binary not found in PATH. May need: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

# --- Clone NemoClaw ---------------------------------------------------------
clone_nemoclaw() {
  NEMOCLAW_DIR="${INSTALL_DIR}/NemoClaw"

  if [[ -d "${NEMOCLAW_DIR}" ]]; then
    info "NemoClaw directory exists. Pulling latest..."
    cd "${NEMOCLAW_DIR}" && git pull --ff-only 2>/dev/null || warn "Git pull failed — using existing checkout."
  else
    info "Cloning NVIDIA NemoClaw..."
    git clone https://github.com/NVIDIA/NemoClaw.git "${NEMOCLAW_DIR}"
  fi

  success "NemoClaw source ready ✓"
}

# --- Run NemoClaw installer -------------------------------------------------
install_nemoclaw() {
  NEMOCLAW_DIR="${INSTALL_DIR}/NemoClaw"
  cd "${NEMOCLAW_DIR}"

  info "Running NemoClaw installer..."
  info "This will:"
  info "  1. Install Node.js dependencies"
  info "  2. Set up the OpenShell gateway"
  info "  3. Configure inference provider"
  info "  4. Create your first sandbox"
  info "  5. Apply baseline security policy"
  info ""

  chmod +x install.sh

  # Build env vars for the installer
  local ENV_VARS=()
  if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
    ENV_VARS+=("NVIDIA_API_KEY=${NVIDIA_API_KEY}")
    info "Using NVIDIA API key from environment."
  elif [[ -f "${HOME}/.nvidia-api-key" ]]; then
    ENV_VARS+=("NVIDIA_API_KEY=$(cat "${HOME}/.nvidia-api-key")")
    info "Using NVIDIA API key from ~/.nvidia-api-key."
  else
    info "No NVIDIA API key. Installer will prompt or use local inference."
  fi

  # Run the installer
  # NOTE: NemoClaw's install.sh runs npm install + nemoclaw onboard.
  # The onboard wizard is interactive — we let it run in the foreground.
  if [[ ${#ENV_VARS[@]} -gt 0 ]]; then
    env "${ENV_VARS[@]}" ./install.sh
  else
    ./install.sh
  fi

  local EXIT_CODE=$?
  if [[ ${EXIT_CODE} -ne 0 ]]; then
    warn "NemoClaw installer exited with code ${EXIT_CODE}."
    warn "This may be OK if it stopped at the onboard wizard."
    warn ""
    warn "If the onboard wizard stopped due to cgroup issues, try:"
    warn "  cd ${NEMOCLAW_DIR}"
    warn "  nemoclaw setup-spark    # fixes Docker cgroup config"
    warn "  nemoclaw onboard        # re-run the setup wizard"
    warn ""
    warn "Continuing with remaining setup steps..."
  fi
}

# --- Post-install: run setup-spark if needed --------------------------------
post_install_fixups() {
  # If nemoclaw is available and the onboard didn't complete,
  # try running setup-spark to fix cgroup issues
  if command -v nemoclaw &>/dev/null 2>&1; then
    success "nemoclaw CLI available ✓"
  else
    NEMOCLAW_DIR="${INSTALL_DIR}/NemoClaw"
    # Check common paths from npm global install
    for BIN_PATH in \
      "${NEMOCLAW_DIR}/node_modules/.bin/nemoclaw" \
      "$(npm root -g 2>/dev/null)/nemoclaw/bin/nemoclaw" \
      "${HOME}/.npm-global/bin/nemoclaw"; do
      if [[ -f "${BIN_PATH}" ]]; then
        export PATH="$(dirname "${BIN_PATH}"):${PATH}"
        success "Found nemoclaw at ${BIN_PATH} ✓"
        break
      fi
    done
  fi
}

# --- Verify installation ----------------------------------------------------
verify() {
  info "Verifying installation..."
  echo ""

  # Check CLIs
  for CMD in nemoclaw openshell; do
    if command -v "${CMD}" &>/dev/null 2>&1; then
      success "${CMD} CLI available ✓"
    else
      warn "${CMD} not found in PATH."
      warn "Try: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
  done

  echo ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  If the onboard wizard didn't fully complete, finish it:"
  info ""
  info "    cd ${INSTALL_DIR}/NemoClaw"
  info "    nemoclaw onboard"
  info ""
  info "  If it stopped on a cgroup error, run this first:"
  info "    nemoclaw setup-spark"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# --- Main -------------------------------------------------------------------
main() {
  mkdir -p "${INSTALL_DIR}"

  fix_cgroup_v2
  clone_openshell
  install_openshell
  clone_nemoclaw
  install_nemoclaw
  post_install_fixups
  verify

  success "NemoClaw deployment phase complete."
}

main "$@"
