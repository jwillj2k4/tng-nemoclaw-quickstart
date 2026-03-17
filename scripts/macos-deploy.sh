#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — macOS Deploy (Phase 2)
#
# Same approach as WSL2: drives openshell directly, bypasses nemoclaw onboard.
# macOS uses Docker Desktop which runs a Linux VM — the sandbox security
# (Landlock/seccomp) works inside the container, not on the host.
#
# USAGE:
#   ./scripts/macos-deploy.sh nvapi-YOUR-NVIDIA-KEY
# ============================================================================

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[TNG]${NC} $1"; }
success() { echo -e "${GREEN}[TNG]${NC} $1"; }
warn()    { echo -e "${YELLOW}[TNG]${NC} $1"; }
fail()    { echo -e "${RED}[TNG]${NC} $1"; exit 1; }

SANDBOX_NAME="tng-nemoclaw"
API_KEY="${1:-}"

if [[ -z "${API_KEY}" ]]; then
  echo ""
  echo -e "${RED}Usage: ./scripts/macos-deploy.sh <NVIDIA_API_KEY>${NC}"
  echo ""
  echo "  Get a free key at: https://build.nvidia.com"
  exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║        TNG NemoClaw — macOS Deploy (Phase 2)             ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Teardown
info "Cleaning up..."
openshell sandbox delete "${SANDBOX_NAME}" 2>/dev/null || true
openshell gateway destroy --name nemoclaw 2>/dev/null || true
docker volume rm openshell-cluster-nemoclaw 2>/dev/null || true
success "Clean ✓"

# Gateway (no --gpu)
info "Starting gateway..."
openshell gateway start --name nemoclaw
success "Gateway ✓"

# Provider
info "Creating inference provider..."
openshell provider create --name nvidia-nim --type nvidia --credential "NVIDIA_API_KEY=${API_KEY}"
success "Provider ✓"

# Inference
info "Setting inference route..."
openshell inference set --provider nvidia-nim --model nvidia/nemotron-3-super-120b-a12b
success "Inference ✓"

# Sandbox
info ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  You're about to enter the sandbox. Run these commands:${NC}"
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}# 1. Configure OpenClaw${NC}"
echo "  openclaw onboard"
echo ""
echo -e "  ${BOLD}  Select:${NC}"
echo "    Provider   → ${BOLD}Custom Provider${NC}"
echo "    Base URL   → ${BOLD}https://inference.local/v1${NC}"
echo "    Compat     → ${BOLD}OpenAI-compatible${NC}"
echo "    Model      → ${BOLD}nvidia/nemotron-3-super-120b-a12b${NC}"
echo "    Endpoint   → ${BOLD}(Enter for default)${NC}"
echo ""
echo -e "  ${BOLD}# 2. Start OpenClaw gateway${NC}"
echo "  mkdir -p /sandbox/.openclaw/workspace/memory"
echo "  echo '# Memory' > /sandbox/.openclaw/workspace/MEMORY.md"
echo "  openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true"
echo "  nohup openclaw gateway run --allow-unconfigured --dev --bind loopback --port 18789 > /tmp/gateway.log 2>&1 &"
echo "  sleep 5"
echo ""
echo -e "  ${BOLD}# 3. Chat${NC}"
echo "  openclaw tui"
echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo ""
info "Connecting..."

openshell sandbox create --name "${SANDBOX_NAME}" --from openclaw
