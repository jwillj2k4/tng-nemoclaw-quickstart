#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Health Check
# NOTE: No set -e. Arithmetic like $((0 + 1)) is safe but ((0++)) is not.
# ============================================================================

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0; FAIL=0; WARN=0
check_pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $1"; WARN=$((WARN + 1)); }

INSTALL_DIR="${HOME}/.tng-nemoclaw"

echo ""
echo -e "${CYAN}${BOLD}TNG NemoClaw Health Check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n${BOLD}System:${NC}"
command -v docker &>/dev/null && docker ps &>/dev/null && check_pass "Docker running" || check_fail "Docker not running"
command -v node &>/dev/null && check_pass "Node.js $(node --version)" || check_fail "Node.js not found"
command -v git &>/dev/null && check_pass "Git installed" || check_fail "Git not found"

echo -e "\n${BOLD}CLIs:${NC}"
command -v nemoclaw &>/dev/null && check_pass "nemoclaw CLI" || check_fail "nemoclaw not in PATH"
command -v openshell &>/dev/null && check_pass "openshell CLI" || check_warn "openshell not in PATH (add ~/.local/bin)"

echo -e "\n${BOLD}Repos:${NC}"
[[ -d "${INSTALL_DIR}/NemoClaw" ]] && check_pass "NemoClaw cloned" || check_fail "NemoClaw not found"
[[ -d "${INSTALL_DIR}/OpenShell" ]] && check_pass "OpenShell cloned" || check_fail "OpenShell not found"

echo -e "\n${BOLD}Gateway:${NC}"
if openshell status &>/dev/null 2>&1; then
  check_pass "Gateway connected"
else
  check_warn "No gateway running (run deploy script)"
fi

echo -e "\n${BOLD}Sandbox:${NC}"
if command -v openshell &>/dev/null; then
  SANDBOX_COUNT=$(openshell sandbox list 2>/dev/null | grep -c "Ready" || true)
  [[ "${SANDBOX_COUNT}" -gt 0 ]] && check_pass "${SANDBOX_COUNT} sandbox(es) ready" || check_warn "No sandboxes (run deploy script)"
fi

echo -e "\n${BOLD}Policies:${NC}"
if [[ -d "${INSTALL_DIR}/policies" ]]; then
  POLICY_COUNT=$(find "${INSTALL_DIR}/policies" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
  check_pass "${POLICY_COUNT} TNG policy templates"
else
  check_warn "Policies not deployed (run setup.sh)"
fi

echo -e "\n${BOLD}Inference:${NC}"
[[ -n "${NVIDIA_API_KEY:-}" ]] && check_pass "NVIDIA API key in env" || \
  ([[ -f "${HOME}/.nvidia-api-key" ]] && check_pass "NVIDIA API key in file" || check_warn "No NVIDIA API key")
command -v nvidia-smi &>/dev/null && \
  check_pass "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo 'detected')" || \
  check_warn "No NVIDIA GPU (cloud inference only)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}${PASS} passed${NC}  ${YELLOW}${WARN} warnings${NC}  ${RED}${FAIL} failed${NC}"
[[ ${FAIL} -gt 0 ]] && exit 1 || exit 0
