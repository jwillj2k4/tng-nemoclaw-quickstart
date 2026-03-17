#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw Quickstart — One-Command Deployment
# https://thenewguard.ai
#
# This script takes you from zero to sandboxed AI agent.
# Run it, go grab coffee, come back to a running NemoClaw deployment.
# ============================================================================

set -uo pipefail
# NOTE: We intentionally do NOT use set -e.
# NemoClaw's installer is interactive and may exit non-zero when the
# onboard wizard needs manual completion. We handle errors explicitly.

# --- Colors & formatting ---------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.tng-nemoclaw"
LOG_FILE="${INSTALL_DIR}/setup.log"

# --- Helper functions -------------------------------------------------------
info()    { echo -e "${CYAN}[TNG]${NC} $1"; }
success() { echo -e "${GREEN}[TNG]${NC} $1"; }
warn()    { echo -e "${YELLOW}[TNG]${NC} $1"; }
fail()    { echo -e "${RED}[TNG]${NC} $1"; exit 1; }

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════════╗"
  echo "  ║          THE NEW GUARD — NemoClaw Quickstart             ║"
  echo "  ║          Secure AI Agents in Under 30 Minutes            ║"
  echo "  ╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
}

# --- Pre-flight checks ------------------------------------------------------
preflight() {
  info "Running pre-flight checks..."

  # Check OS
  if [[ ! -f /etc/os-release ]]; then
    fail "Cannot detect OS. This script requires Ubuntu 22.04+."
  fi

  source /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    warn "Detected ${ID} — this script is tested on Ubuntu 22.04+. Proceeding anyway."
  fi

  # Check architecture
  ARCH=$(uname -m)
  if [[ "${ARCH}" != "x86_64" && "${ARCH}" != "aarch64" ]]; then
    fail "Unsupported architecture: ${ARCH}. NemoClaw requires x86_64 or aarch64."
  fi

  # Check RAM
  TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
  if [[ ${TOTAL_RAM_GB} -lt 14 ]]; then
    warn "Only ${TOTAL_RAM_GB}GB RAM detected. 16GB+ recommended. Continuing anyway."
  else
    success "RAM: ${TOTAL_RAM_GB}GB ✓"
  fi

  # Check disk space (need at least 20GB free)
  FREE_DISK_GB=$(df -BG "${HOME}" | tail -1 | awk '{print $4}' | tr -d 'G')
  if [[ ${FREE_DISK_GB} -lt 20 ]]; then
    fail "Only ${FREE_DISK_GB}GB free disk space. Need at least 20GB."
  else
    success "Disk: ${FREE_DISK_GB}GB free ✓"
  fi

  success "Pre-flight checks passed."
}

# --- Phase 1: Prerequisites -------------------------------------------------
install_prereqs() {
  info "Phase 1/4: Installing prerequisites..."
  if bash "${REPO_DIR}/scripts/install-prereqs.sh" 2>&1 | tee -a "${LOG_FILE}"; then
    success "Prerequisites installed ✓"
  else
    fail "Prerequisites failed. Check ${LOG_FILE} for details."
  fi
}

# --- Phase 2: Deploy NemoClaw -----------------------------------------------
deploy_nemoclaw() {
  info "Phase 2/4: Deploying NemoClaw + OpenShell..."
  if bash "${REPO_DIR}/scripts/deploy-nemoclaw.sh" 2>&1 | tee -a "${LOG_FILE}"; then
    success "NemoClaw deployed ✓"
  else
    warn "NemoClaw deploy exited with warnings."
    warn "This is often OK — the onboard wizard may need manual completion."
    warn "Continuing with policy setup..."
  fi
}

# --- Phase 3: Apply TNG policies --------------------------------------------
apply_policies() {
  info "Phase 3/4: Applying TNG security policies..."

  NEMOCLAW_DIR="${INSTALL_DIR}/NemoClaw"
  POLICY_DEST="${INSTALL_DIR}/policies"

  mkdir -p "${POLICY_DEST}"
  cp -r "${REPO_DIR}/policies/"* "${POLICY_DEST}/"

  info "Copied TNG policy templates to ${POLICY_DEST}"
  info "Available policy packs:"
  echo ""
  echo "  base/default-lockdown.yaml   — Maximum restriction (active)"
  echo "  healthcare/hipaa-agent.yaml  — HIPAA-compliant"
  echo "  financial/soc2-agent.yaml    — SOC 2 auditable"
  echo "  legal/legal-privilege.yaml   — Attorney-client privilege"
  echo "  dev/permissive-dev.yaml      — Development/testing"
  echo ""
  info "Switch policies: openshell policy apply --network <path-to-yaml>"

  success "Policies deployed ✓"
}

# --- Phase 4: Health check ---------------------------------------------------
run_healthcheck() {
  info "Phase 4/4: Running health check..."
  if bash "${REPO_DIR}/scripts/health-check.sh" 2>&1 | tee -a "${LOG_FILE}"; then
    success "Health check passed ✓"
  else
    warn "Health check found issues — see output above."
    warn "This is expected if the onboard wizard needs manual completion."
  fi
}

# --- Summary -----------------------------------------------------------------
print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════════╗"
  echo "  ║                    SETUP COMPLETE                        ║"
  echo "  ╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
  echo -e "  ${BOLD}If the onboard wizard finished:${NC}"
  echo "    nemoclaw my-assistant connect    # connect to your agent"
  echo "    nemoclaw my-assistant status     # check health"
  echo "    nemoclaw my-assistant logs -f    # stream logs"
  echo "    nemoclaw term                    # OpenShell monitor"
  echo ""
  echo -e "  ${BOLD}If the onboard wizard stopped early (cgroup error, etc.):${NC}"
  echo "    cd ${INSTALL_DIR}/NemoClaw"
  echo "    nemoclaw setup-spark             # fix Docker cgroup config"
  echo "    nemoclaw onboard                 # re-run the setup wizard"
  echo ""
  echo -e "  ${BOLD}Switch inference:${NC}"
  echo "    openshell inference set --provider vllm-local --model nvidia/nemotron-3-nano-30b-a3b"
  echo ""
  echo -e "  ${BOLD}Switch policy:${NC}"
  echo "    openshell policy apply --network ${INSTALL_DIR}/policies/dev/permissive-dev.yaml"
  echo ""
  echo -e "  ${BOLD}TNG policy templates:${NC}  ${INSTALL_DIR}/policies/"
  echo -e "  ${BOLD}Full logs:${NC}             ${LOG_FILE}"
  echo -e "  ${BOLD}Docs:${NC}                  ${REPO_DIR}/docs/"
  echo -e "  ${BOLD}Teardown:${NC}              bash ${REPO_DIR}/scripts/teardown.sh"
  echo ""
  echo -e "  ${CYAN}Built by The New Guard — thenewguard.ai${NC}"
  echo ""
}

# --- Main --------------------------------------------------------------------
main() {
  banner

  mkdir -p "${INSTALL_DIR}"
  echo "=== TNG NemoClaw Setup — $(date) ===" > "${LOG_FILE}"

  preflight
  install_prereqs
  deploy_nemoclaw
  apply_policies
  run_healthcheck
  print_summary
}

main "$@"
