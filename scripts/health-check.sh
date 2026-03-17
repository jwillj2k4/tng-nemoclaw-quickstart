#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Health Check
# Verifies the entire stack is running correctly
#
# NOTE: We do NOT use set -e here. The counter functions use arithmetic
# that can return exit code 1 (e.g. ((0++)) is falsy in bash), and
# individual check failures should not kill the script.
# ============================================================================

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

# Use $((x + 1)) instead of ((x++)) — post-increment from 0 returns
# exit code 1 in bash, which kills scripts under set -e.
check_pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $1"; WARN=$((WARN + 1)); }

INSTALL_DIR="${HOME}/.tng-nemoclaw"

echo ""
echo -e "${CYAN}${BOLD}TNG NemoClaw Health Check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# --- System checks ----------------------------------------------------------
echo ""
echo -e "${BOLD}System:${NC}"

if command -v docker &>/dev/null && docker ps &>/dev/null; then
  check_pass "Docker running"
else
  check_fail "Docker not running"
fi

if command -v node &>/dev/null; then
  check_pass "Node.js $(node --version)"
else
  check_fail "Node.js not found"
fi

if command -v git &>/dev/null; then
  check_pass "Git installed"
else
  check_fail "Git not found"
fi

# cgroup check (Linux/WSL2 only)
if [[ "$(uname -s)" != "Darwin" ]] && [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
  if [[ -f /etc/docker/daemon.json ]] && \
     jq -e '.["default-cgroupns-mode"] == "host"' /etc/docker/daemon.json &>/dev/null; then
    check_pass "Docker cgroupns=host configured"
  else
    check_warn "Docker cgroupns=host not set — run: nemoclaw setup-spark"
  fi
fi

# --- NemoClaw checks --------------------------------------------------------
echo ""
echo -e "${BOLD}NemoClaw:${NC}"

if command -v nemoclaw &>/dev/null; then
  check_pass "nemoclaw CLI in PATH"
else
  check_fail "nemoclaw CLI not found — try: cd ~/.tng-nemoclaw/NemoClaw && npm link"
fi

if [[ -d "${INSTALL_DIR}/NemoClaw" ]]; then
  check_pass "NemoClaw repo cloned"
else
  check_fail "NemoClaw repo not found"
fi

# --- OpenShell checks -------------------------------------------------------
echo ""
echo -e "${BOLD}OpenShell:${NC}"

if command -v openshell &>/dev/null; then
  check_pass "openshell CLI in PATH"
else
  check_warn "openshell not in PATH — add ~/.local/bin to PATH"
fi

if [[ -d "${INSTALL_DIR}/OpenShell" ]]; then
  check_pass "OpenShell repo cloned"
else
  check_fail "OpenShell repo not found"
fi

# --- Sandbox checks ---------------------------------------------------------
echo ""
echo -e "${BOLD}Sandbox:${NC}"

if command -v nemoclaw &>/dev/null; then
  if nemoclaw my-assistant status &>/dev/null 2>&1; then
    check_pass "Sandbox 'my-assistant' running"
  else
    check_warn "Sandbox not running (expected if onboard hasn't completed)"
  fi
else
  check_warn "Can't check sandbox — nemoclaw CLI not in PATH"
fi

if command -v openshell &>/dev/null; then
  SANDBOX_COUNT=$(openshell sandbox list 2>/dev/null | grep -c "running" || true)
  if [[ "${SANDBOX_COUNT}" -gt 0 ]]; then
    check_pass "${SANDBOX_COUNT} sandbox(es) running"
  else
    check_warn "No running sandboxes"
  fi
fi

# --- Policy checks ----------------------------------------------------------
echo ""
echo -e "${BOLD}Policies:${NC}"

POLICY_DIR="${INSTALL_DIR}/policies"
if [[ -d "${POLICY_DIR}" ]]; then
  POLICY_COUNT=$(find "${POLICY_DIR}" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
  check_pass "${POLICY_COUNT} TNG policy templates available"
else
  check_warn "TNG policies not deployed (run setup.sh)"
fi

# --- Inference checks -------------------------------------------------------
echo ""
echo -e "${BOLD}Inference:${NC}"

if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
  check_pass "NVIDIA API key set in environment"
elif [[ -f "${HOME}/.nvidia-api-key" ]]; then
  check_pass "NVIDIA API key found at ~/.nvidia-api-key"
else
  check_warn "No NVIDIA API key — cloud inference won't work"
fi

if command -v nvidia-smi &>/dev/null; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)
  if [[ -n "${GPU_NAME}" ]]; then
    check_pass "NVIDIA GPU: ${GPU_NAME}"
  else
    check_warn "nvidia-smi present but no GPU detected"
  fi
else
  check_warn "No NVIDIA GPU — local Nemotron inference unavailable"
fi

# --- Summary ----------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}${PASS} passed${NC}  ${YELLOW}${WARN} warnings${NC}  ${RED}${FAIL} failed${NC}"

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo -e "  ${RED}Some checks failed. See docs/TROUBLESHOOTING.md${NC}"
  exit 1
elif [[ ${WARN} -gt 0 ]]; then
  echo ""
  echo -e "  ${YELLOW}Warnings present but not blocking.${NC}"
  exit 0
else
  echo ""
  echo -e "  ${GREEN}All checks passed. Stack is healthy.${NC}"
  exit 0
fi
