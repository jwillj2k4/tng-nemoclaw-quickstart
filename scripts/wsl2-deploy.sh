#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — WSL2 Deploy (Phase 2)
#
# Bypasses `nemoclaw onboard` entirely because it forces --gpu on WSL2,
# which kills every sandbox. This script drives `openshell` directly.
#
# USAGE:
#   ./scripts/wsl2-deploy.sh nvapi-YOUR-NVIDIA-KEY
#
# WHAT IT DOES:
#   1. Tears down any stale gateways/sandboxes/volumes
#   2. Starts OpenShell gateway WITHOUT --gpu
#   3. Creates NVIDIA inference provider
#   4. Sets inference routing through OpenShell proxy
#   5. Creates sandbox WITHOUT --gpu (stays alive!)
#   6. Auto-connects you to the sandbox
#   7. Inside: you run openclaw onboard → Custom Provider → inference.local
#
# WHY THIS EXISTS:
#   NemoClaw v0.0.7 detects nvidia-smi on WSL2 and forces --gpu on
#   gateway start AND sandbox creation. Docker Desktop on WSL2 can't pass
#   the GPU through to the k3s cluster inside the gateway container.
#   The sandbox is DOA every time. This is confirmed by multiple users:
#   https://forums.developer.nvidia.com/t/363769
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
  echo -e "${RED}Usage: ./scripts/wsl2-deploy.sh <NVIDIA_API_KEY>${NC}"
  echo ""
  echo "  Get a free key at: https://build.nvidia.com"
  echo "  Key starts with: nvapi-"
  echo ""
  exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║     TNG NemoClaw — WSL2 Deploy (GPU bug workaround)     ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================================
# STEP 1: NUCLEAR TEARDOWN
# ============================================================================
info "Step 1/5: Cleaning up stale state..."

openshell sandbox delete "${SANDBOX_NAME}" 2>/dev/null && info "  Deleted sandbox '${SANDBOX_NAME}'" || true
openshell gateway destroy --name nemoclaw 2>/dev/null && info "  Destroyed gateway 'nemoclaw'" || true
openshell gateway destroy --name openshell 2>/dev/null && info "  Destroyed gateway 'openshell'" || true
docker volume rm openshell-cluster-nemoclaw 2>/dev/null && info "  Removed volume" || true
docker volume rm openshell-cluster-openshell 2>/dev/null || true

success "Clean slate ✓"
echo ""

# ============================================================================
# STEP 2: START GATEWAY (NO --gpu)
# ============================================================================
info "Step 2/5: Starting OpenShell gateway (without --gpu)..."

openshell gateway start --name nemoclaw
if ! openshell status &>/dev/null; then
  fail "Gateway failed to start. Try: openshell doctor check"
fi

success "Gateway running ✓"
echo ""

# ============================================================================
# STEP 3: CREATE INFERENCE PROVIDER
# ============================================================================
info "Step 3/5: Configuring NVIDIA inference provider..."

openshell provider create \
  --name nvidia-nim \
  --type nvidia \
  --credential "NVIDIA_API_KEY=${API_KEY}"

success "Provider created ✓"
echo ""

# ============================================================================
# STEP 4: SET INFERENCE ROUTING
# ============================================================================
info "Step 4/5: Setting inference route..."

openshell inference set \
  --provider nvidia-nim \
  --model nvidia/nemotron-3-super-120b-a12b

success "Inference route → nvidia/nemotron-3-super-120b-a12b ✓"
echo ""

# ============================================================================
# STEP 5: CREATE SANDBOX + CONNECT
# ============================================================================
info "Step 5/5: Creating sandbox (without --gpu)..."
info ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  You're about to enter the sandbox. Run these commands:${NC}"
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}# 1. Configure OpenClaw (interactive wizard)${NC}"
echo "  openclaw onboard"
echo ""
echo -e "  ${BOLD}  When prompted:${NC}"
echo "    Model/auth provider → ${BOLD}Custom Provider${NC}"
echo "    API Base URL        → ${BOLD}https://inference.local/v1${NC}"
echo "    Compatibility       → ${BOLD}OpenAI-compatible${NC}"
echo "    Model ID            → ${BOLD}nvidia/nemotron-3-super-120b-a12b${NC}"
echo "    Endpoint ID         → ${BOLD}(press Enter for default)${NC}"
echo "    Web search          → ${BOLD}(skip)${NC}"
echo ""
echo -e "  ${BOLD}# 2. Start the OpenClaw gateway${NC}"
echo "  mkdir -p /sandbox/.openclaw/workspace/memory"
echo "  echo '# Memory' > /sandbox/.openclaw/workspace/MEMORY.md"
echo "  openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true"
echo "  nohup openclaw gateway run --allow-unconfigured --dev --bind loopback --port 18789 > /tmp/gateway.log 2>&1 &"
echo "  sleep 5"
echo ""
echo -e "  ${BOLD}# 3. Launch the chat interface${NC}"
echo "  openclaw tui"
echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo ""
info "Connecting to sandbox now..."
echo ""

# This auto-connects — user lands inside the sandbox shell
openshell sandbox create --name "${SANDBOX_NAME}" --from openclaw
