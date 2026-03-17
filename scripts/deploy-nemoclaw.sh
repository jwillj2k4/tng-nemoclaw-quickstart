#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Deploy NemoClaw + OpenShell
# macOS (Docker Desktop), native Linux, and WSL2
#
# FLOW:
#   1. Clone and install CLIs (OpenShell + NemoClaw) — always works
#   2. Gate: verify cgroup is configured — fix it or stop
#   3. Run nemoclaw onboard — only if cgroup is ready
#
# The key insight: NemoClaw's install.sh bundles "npm install" and "onboard"
# together. We separate them so we can fix cgroup BETWEEN the two steps.
# ============================================================================

set -uo pipefail

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
OS_TYPE="linux"
IS_DOCKER_DESKTOP=false

case "$(uname -s)" in
  Darwin)
    OS_TYPE="macos"
    IS_DOCKER_DESKTOP=true
    ;;
  Linux)
    if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
      OS_TYPE="wsl2"
    fi
    ;;
esac

# Detect Docker Desktop on Linux/WSL2
if [[ "${OS_TYPE}" != "macos" ]]; then
  if [[ ! -d "/etc/docker" ]] || docker info 2>/dev/null | grep -qi "docker desktop\|desktop-linux"; then
    IS_DOCKER_DESKTOP=true
  fi
fi

# ============================================================================
# STEP 1: Clone and install CLIs
# These steps have no cgroup dependency — they always work.
# ============================================================================

clone_openshell() {
  local DIR="${INSTALL_DIR}/OpenShell"
  if [[ -d "${DIR}" ]]; then
    info "OpenShell exists. Pulling latest..."
    cd "${DIR}" && git pull --ff-only 2>/dev/null || warn "Pull failed — using existing."
  else
    info "Cloning NVIDIA OpenShell..."
    git clone https://github.com/NVIDIA/OpenShell.git "${DIR}"
  fi
  success "OpenShell source ready ✓"
}

install_openshell() {
  local DIR="${INSTALL_DIR}/OpenShell"
  cd "${DIR}"
  info "Installing OpenShell CLI..."

  if [[ -f "install.sh" ]]; then
    chmod +x install.sh
    bash install.sh
  elif [[ -f "Makefile" ]]; then
    make build
  fi

  # Ensure it's in PATH
  if ! command -v openshell &>/dev/null; then
    if [[ -f "${HOME}/.local/bin/openshell" ]]; then
      export PATH="${HOME}/.local/bin:${PATH}"
    fi
  fi

  if command -v openshell &>/dev/null; then
    success "openshell CLI ✓"
  else
    warn "openshell not found in PATH. Add ~/.local/bin to your PATH."
  fi
}

clone_nemoclaw() {
  local DIR="${INSTALL_DIR}/NemoClaw"
  if [[ -d "${DIR}" ]]; then
    info "NemoClaw exists. Pulling latest..."
    cd "${DIR}" && git pull --ff-only 2>/dev/null || warn "Pull failed — using existing."
  else
    info "Cloning NVIDIA NemoClaw..."
    git clone https://github.com/NVIDIA/NemoClaw.git "${DIR}"
  fi
  success "NemoClaw source ready ✓"
}

install_nemoclaw_cli() {
  # Install the CLI ONLY — no onboard. We handle onboard separately after
  # verifying cgroup is ready.
  local DIR="${INSTALL_DIR}/NemoClaw"
  cd "${DIR}"

  info "Installing NemoClaw CLI (npm dependencies)..."

  # npm install + link to get the nemoclaw binary
  npm install 2>&1 | tail -5
  npm link 2>&1 || sudo npm link 2>&1 || true

  # Find nemoclaw in PATH
  if ! command -v nemoclaw &>/dev/null; then
    # Check nvm paths and common locations
    for BIN_PATH in \
      "${DIR}/node_modules/.bin/nemoclaw" \
      "$(npm root -g 2>/dev/null || echo /dev/null)/nemoclaw/bin/nemoclaw" \
      "${HOME}/.npm-global/bin/nemoclaw" \
      "/usr/local/bin/nemoclaw"; do
      if [[ -f "${BIN_PATH}" ]]; then
        export PATH="$(dirname "${BIN_PATH}"):${PATH}"
        break
      fi
    done
  fi

  if command -v nemoclaw &>/dev/null; then
    success "nemoclaw CLI ✓"
  else
    warn "nemoclaw CLI not found in PATH after install."
    warn "Try: npm link (from ${DIR})"
  fi
}

# ============================================================================
# STEP 2: Ensure cgroup is ready
# This is the gate. We do NOT proceed to onboard unless this passes.
# ============================================================================

# Returns 0 if cgroup is ready for OpenShell, 1 if not.
check_cgroup_ready() {
  # macOS: Docker Desktop handles cgroups internally — always ready
  if [[ "${OS_TYPE}" == "macos" ]]; then
    return 0
  fi

  # cgroup v1: no issue
  if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
    return 0
  fi

  # cgroup v2: check if cgroupns=host is configured
  # Method 1: check daemon.json directly
  if [[ -f /etc/docker/daemon.json ]]; then
    local MODE
    MODE=$(jq -r '.["default-cgroupns-mode"] // empty' /etc/docker/daemon.json 2>/dev/null || true)
    if [[ "${MODE}" == "host" ]]; then
      return 0
    fi
  fi

  # Not configured
  return 1
}

ensure_cgroup_ready() {
  info "Checking cgroup configuration..."

  if check_cgroup_ready; then
    success "cgroup ready for OpenShell ✓"
    return 0
  fi

  info "cgroup v2 detected — cgroupns=host not configured yet."
  info ""

  if ! command -v nemoclaw &>/dev/null; then
    warn "nemoclaw CLI not available — can't run setup-spark."
    warn "Fix manually: see docs/TROUBLESHOOTING.md"
    return 1
  fi

  # Try NemoClaw's own fix tool
  info "Running 'nemoclaw setup-spark' to configure Docker..."
  local DIR="${INSTALL_DIR}/NemoClaw"
  cd "${DIR}"

  nemoclaw setup-spark 2>&1 || true

  # On Docker Desktop, we can't restart the daemon from inside WSL2/macOS.
  # The user needs to restart Docker Desktop themselves.
  if [[ "${IS_DOCKER_DESKTOP}" == true ]]; then
    info ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "  ${BOLD}Action required: Restart Docker Desktop${NC}"
    info ""
    info "  nemoclaw setup-spark created the config, but Docker Desktop"
    info "  needs to be restarted to pick it up."
    info ""
    if [[ "${OS_TYPE}" == "wsl2" ]]; then
      info "  Option A — Restart from Windows:"
      info "    Right-click Docker Desktop tray icon → Restart"
      info ""
      info "  Option B — Set it in Docker Desktop UI:"
      info "    Settings → Docker Engine → add to JSON:"
      info "    \"default-cgroupns-mode\": \"host\""
      info "    Click 'Apply & Restart'"
    else
      info "  Click the Docker Desktop icon → Restart"
    fi
    info ""
    info "  After Docker restarts, run:"
    info "    ${BOLD}nemoclaw onboard${NC}"
    info ""
    info "  Or re-run this script:"
    info "    ${BOLD}./setup.sh${NC}"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return 1
  fi

  # Native Linux: we can restart Docker ourselves
  info "Restarting Docker..."
  if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    sudo systemctl restart docker
  else
    sudo service docker restart
  fi

  # Wait for Docker to come back
  local retries=0
  while ! docker ps &>/dev/null 2>&1; do
    retries=$((retries + 1))
    if [[ ${retries} -gt 15 ]]; then
      warn "Docker didn't come back after restart."
      return 1
    fi
    sleep 2
  done

  # Verify the fix worked
  if check_cgroup_ready; then
    success "Docker restarted with cgroupns=host ✓"
    return 0
  else
    warn "Config was written but Docker didn't pick it up."
    warn "Try: sudo service docker restart"
    return 1
  fi
}

# ============================================================================
# STEP 3: Run onboard
# Only called if cgroup is ready.
# ============================================================================

run_onboard() {
  local DIR="${INSTALL_DIR}/NemoClaw"
  cd "${DIR}"

  info "Running NemoClaw onboard wizard..."
  info ""

  # Pass NVIDIA API key if available
  if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
    NVIDIA_API_KEY="${NVIDIA_API_KEY}" nemoclaw onboard
  elif [[ -f "${HOME}/.nvidia-api-key" ]]; then
    NVIDIA_API_KEY="$(cat "${HOME}/.nvidia-api-key")" nemoclaw onboard
  else
    nemoclaw onboard
  fi

  local EXIT_CODE=$?
  if [[ ${EXIT_CODE} -eq 0 ]]; then
    success "NemoClaw onboard complete ✓"
  else
    warn "Onboard exited with code ${EXIT_CODE}."
    warn "You can re-run it: nemoclaw onboard"
  fi
  return ${EXIT_CODE}
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  mkdir -p "${INSTALL_DIR}"

  # Step 1: Install CLIs (no cgroup dependency)
  info "Step 1/3: Installing CLIs..."
  clone_openshell
  install_openshell
  clone_nemoclaw
  install_nemoclaw_cli
  echo ""

  # Step 2: Gate on cgroup
  info "Step 2/3: Checking Docker cgroup configuration..."
  if ! ensure_cgroup_ready; then
    warn ""
    warn "Stopping here — cgroup must be fixed before onboard can run."
    warn "CLIs are installed. Fix cgroup (see above), then run:"
    warn "  nemoclaw onboard"
    warn "  # or re-run: ./setup.sh"
    echo ""
    # Exit with a special code so setup.sh knows this is a "fix and retry" situation
    exit 2
  fi
  echo ""

  # Step 3: Onboard (only if cgroup is ready)
  info "Step 3/3: Running NemoClaw onboard..."
  run_onboard
  local ONBOARD_EXIT=$?

  echo ""
  if [[ ${ONBOARD_EXIT} -eq 0 ]]; then
    success "NemoClaw deployment complete ✓"
  else
    warn "NemoClaw deployed but onboard needs attention."
    warn "Run: nemoclaw onboard"
  fi
}

main "$@"
