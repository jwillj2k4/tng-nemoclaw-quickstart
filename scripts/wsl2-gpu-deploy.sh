#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — WSL2 GPU Deploy (Phase 2 — Experimental)
#
# Enables actual GPU passthrough on WSL2 by patching the CDI pipeline
# inside the OpenShell gateway. First confirmed working on RTX 5090.
#
# USAGE:
#   ./scripts/wsl2-gpu-deploy.sh [NVIDIA_API_KEY]
#
#   API key is optional. Without it, sandbox has GPU but no cloud inference.
#   With it, cloud inference is configured through inference.local proxy.
#
# WHAT IT DOES:
#   1. Tears down stale state
#   2. Starts OpenShell gateway WITH --gpu
#   3. Waits for core gateway pods
#   4. Generates CDI spec + patches it (UUID device entry + libdxcore.so)
#   5. Copies CDI spec to /etc/cdi for containerd
#   6. Switches nvidia runtime to CDI mode
#   7. Enables CDI in containerd config
#   8. Restarts containerd to pick up changes
#   9. Labels k3s node for device plugin scheduling
#  10. Waits for nvidia-device-plugin to reach Running
#  11. Creates provider + GPU-enabled sandbox
#
# WHY THIS EXISTS:
#   WSL2 virtualises GPU access through /dev/dxg instead of /dev/nvidia*.
#   Three things break: NFD can't see PCI, nvidia runtime "auto" mode
#   misses libdxcore.so, and nvidia-ctk doesn't generate UUID device entries.
#
#   Root cause: https://github.com/NVIDIA/OpenShell/issues/404
#   nvidia-ctk bug: https://github.com/NVIDIA/nvidia-container-toolkit/issues/1739
#
# STATUS: EXPERIMENTAL — confirmed working on RTX 5090 Laptop (24GB), WSL2
#         Ubuntu 24.04, Docker Desktop, OpenShell 0.0.7.
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

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║  TNG NemoClaw — WSL2 GPU Deploy (Experimental)          ║"
echo "  ║  Local GPU passthrough via CDI pipeline patching         ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

warn "This is experimental. If it fails, fall back to:"
warn "  ./scripts/wsl2-deploy.sh nvapi-YOUR-KEY (cloud inference, stable)"
echo ""

# ============================================================================
# PREFLIGHT
# ============================================================================
info "Preflight checks..."

if ! grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
  fail "Not running on WSL2."
fi
success "WSL2 detected ✓"

if ! command -v nvidia-smi &>/dev/null; then
  fail "nvidia-smi not found."
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1)
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
success "GPU: ${GPU_NAME:-unknown} (${GPU_MEM:-?} MB) ✓"

if [[ ! -e /dev/dxg ]]; then
  warn "/dev/dxg not found — GPU bridge may not be available."
fi

echo ""

# ============================================================================
# STEP 1: TEARDOWN
# ============================================================================
info "Step 1/11: Cleaning up stale state..."

openshell sandbox delete "${SANDBOX_NAME}" 2>/dev/null && info "  Deleted sandbox" || true
openshell gateway destroy --name nemoclaw 2>/dev/null && info "  Destroyed gateway" || true
openshell gateway destroy --name openshell 2>/dev/null || true
docker volume rm openshell-cluster-nemoclaw 2>/dev/null && info "  Removed volume" || true
docker volume rm openshell-cluster-openshell 2>/dev/null || true

success "Clean slate ✓"
echo ""

# ============================================================================
# STEP 2: START GATEWAY WITH --gpu
# ============================================================================
info "Step 2/11: Starting OpenShell gateway (with --gpu)..."

openshell gateway start --name nemoclaw --gpu

for i in $(seq 1 10); do
  if openshell status 2>&1 | grep -q "Connected"; then break; fi
  [[ "$i" -eq 10 ]] && fail "Gateway failed to become healthy."
  sleep 2
done

success "Gateway running with --gpu ✓"
echo ""

# ============================================================================
# STEP 3: WAIT FOR CORE PODS
# ============================================================================
info "Step 3/11: Waiting for core gateway pods..."

for i in $(seq 1 30); do
  READY=$(openshell doctor exec -- kubectl get pods -A --no-headers 2>/dev/null \
    | tr -d '\r' | grep -c "Running" || true)
  [[ "$READY" -ge 3 ]] && break
  sleep 2
done

success "Core pods ready (${READY:-0} running) ✓"
echo ""

# ============================================================================
# STEP 4: GENERATE + PATCH CDI SPEC
# ============================================================================
info "Step 4/11: Generating and patching CDI spec for WSL2..."

# Generate clean CDI spec
openshell doctor exec -- nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml 2>&1 \
  | grep -E "INFO|WARN" | head -5

# Get GPU UUID from inside gateway
GPU_UUID=$(openshell doctor exec -- nvidia-smi --query-gpu=uuid --format=csv,noheader,nounits 2>/dev/null \
  | tr -d '\r' | head -1)

if [[ -z "$GPU_UUID" ]]; then
  warn "Could not get GPU UUID — CDI spec will only have 'all' device."
else
  info "  GPU UUID: ${GPU_UUID}"
fi

# Find libdxcore inside gateway
CONTAINER_LIBDXCORE=$(openshell doctor exec -- sh -c \
  'find /usr/lib -name "libdxcore.so" 2>/dev/null | head -1' | tr -d '\r')

if [[ -z "$CONTAINER_LIBDXCORE" ]]; then
  CONTAINER_LIBDXCORE="/usr/lib/x86_64-linux-gnu/libdxcore.so"
  warn "libdxcore.so not found in container, trying: ${CONTAINER_LIBDXCORE}"
fi
info "  libdxcore.so: ${CONTAINER_LIBDXCORE}"

# Patch CDI spec using awk (handles YAML structure safely)
# Inserts UUID device entry after the "all" device and appends libdxcore mount
openshell doctor exec -- sh -c "
awk -v uuid='${GPU_UUID}' -v libdxcore='${CONTAINER_LIBDXCORE}' '
  # Insert UUID device after the all device block (after first /dev/dxg line)
  /- path: \/dev\/dxg/ && !uuid_added {
    print
    if (uuid != \"\") {
      print \"    - name: \" uuid
      print \"      containerEdits:\"
      print \"        deviceNodes:\"
      print \"            - path: /dev/dxg\"
    }
    uuid_added = 1
    next
  }
  # Add --folder for libdxcore to the update-ldcache hook
  /- --folder/ && !folder_added {
    print
    dir = libdxcore
    sub(/\/[^\/]*\$/, \"\", dir)
    print \"            - --folder\"
    print \"            - \" dir
    folder_added = 1
    next
  }
  { print }
  # Append libdxcore mount at end of file
  END {
    print \"        - hostPath: \" libdxcore
    print \"          containerPath: \" libdxcore
    print \"          options:\"
    print \"            - ro\"
    print \"            - nosuid\"
    print \"            - nodev\"
    print \"            - rbind\"
    print \"            - rprivate\"
  }
' /var/run/cdi/nvidia.yaml > /tmp/nvidia-patched.yaml && \
mv /tmp/nvidia-patched.yaml /var/run/cdi/nvidia.yaml && \
echo 'CDI spec patched successfully' || echo 'CDI patching failed'
"

# Verify
CDI_COUNT=$(openshell doctor exec -- nvidia-ctk cdi list 2>&1 | tr -d '\r' | grep -c "nvidia.com/gpu" || true)
if [[ "$CDI_COUNT" -ge 1 ]]; then
  success "CDI spec valid — ${CDI_COUNT} device(s) ✓"
else
  warn "CDI spec may be invalid. Continuing anyway..."
fi

echo ""

# ============================================================================
# STEP 5: COPY CDI SPEC TO /etc/cdi
# ============================================================================
info "Step 5/11: Copying CDI spec to /etc/cdi..."

openshell doctor exec -- mkdir -p /etc/cdi
openshell doctor exec -- cp /var/run/cdi/nvidia.yaml /etc/cdi/nvidia.yaml

success "CDI spec copied ✓"
echo ""

# ============================================================================
# STEP 6: SWITCH NVIDIA RUNTIME TO CDI MODE
# ============================================================================
info "Step 6/11: Switching nvidia runtime to CDI mode..."

openshell doctor exec -- \
  sed -i 's/mode = "auto"/mode = "cdi"/' /etc/nvidia-container-runtime/config.toml 2>/dev/null \
  || warn "Could not patch runtime config"

MODE=$(openshell doctor exec -- grep 'mode =' /etc/nvidia-container-runtime/config.toml 2>/dev/null \
  | tr -d '\r' | head -1)
info "  Runtime: ${MODE:-unknown}"

success "Runtime mode set ✓"
echo ""

# ============================================================================
# STEP 7: ENABLE CDI IN CONTAINERD
# ============================================================================
info "Step 7/11: Enabling CDI in containerd config..."

openshell doctor exec -- sh -c '
mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
cat > /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl << "TMPL"
[plugins."io.containerd.grpc.v1.cri"]
  enable_cdi = true
TMPL
'

success "containerd CDI enabled ✓"
echo ""

# ============================================================================
# STEP 8: RESTART CONTAINERD
# ============================================================================
info "Step 8/11: Restarting containerd to pick up CDI/runtime changes..."
warn "This takes ~15 seconds..."

openshell doctor exec -- sh -c '
  CPID=$(pgrep -f "containerd -c /var/lib/rancher" 2>/dev/null | head -1)
  if [ -n "$CPID" ]; then
    echo "Restarting containerd (PID $CPID)..."
    kill $CPID 2>/dev/null
  else
    echo "containerd PID not found, sending SIGHUP to PID 1..."
    kill -HUP 1 2>/dev/null || true
  fi
' 2>&1 || true

sleep 8

K3S_READY=false
for i in $(seq 1 30); do
  if openshell doctor exec -- kubectl get nodes --no-headers 2>/dev/null | tr -d '\r' | grep -q "Ready"; then
    K3S_READY=true
    break
  fi
  [[ $((i % 5)) -eq 0 ]] && info "  Still waiting for k3s... (${i}/30)"
  sleep 2
done

$K3S_READY && success "containerd restarted ✓" || warn "k3s may not have fully recovered."

# Wait for pods to stabilize
info "  Waiting for pods to stabilize..."
for i in $(seq 1 20); do
  RUNNING=$(openshell doctor exec -- kubectl get pods -A --no-headers 2>/dev/null \
    | tr -d '\r' | grep -c "Running" || true)
  [[ "$RUNNING" -ge 3 ]] && break
  sleep 2
done

# Force reschedule nvidia pods with new CDI config
info "  Cleaning up old nvidia pods..."
openshell doctor exec -- kubectl delete pods -n nvidia-device-plugin --all --force 2>/dev/null || true
sleep 3

success "Pods stabilized (${RUNNING:-0} running) ✓"
echo ""

# ============================================================================
# STEP 9: LABEL K3S NODE
# ============================================================================
info "Step 9/11: Labeling k3s node for nvidia device plugin..."

NODE_NAME=$(openshell doctor exec -- kubectl get nodes --no-headers -o custom-columns=":metadata.name" 2>/dev/null \
  | tr -d '\r\n' | awk '{print $1}')

if [[ -z "$NODE_NAME" ]]; then
  warn "Could not determine k3s node name."
else
  openshell doctor exec -- kubectl label node "${NODE_NAME}" \
    feature.node.kubernetes.io/pci-10de.present=true --overwrite 2>&1 || true
  success "Node '${NODE_NAME}' labeled ✓"
fi
echo ""

# ============================================================================
# STEP 10: WAIT FOR NVIDIA DEVICE PLUGIN
# ============================================================================
info "Step 10/11: Waiting for nvidia-device-plugin (up to 90s)..."

GPU_READY=false
for i in $(seq 1 45); do
  DP_STATUS=$(openshell doctor exec -- \
    kubectl get pods -n nvidia-device-plugin --no-headers 2>/dev/null \
    | tr -d '\r' | grep "nvidia-device-plugin " | grep -v "discovery\|gc\|mps\|worker\|master" | head -1)

  if echo "$DP_STATUS" | grep -q "Running"; then
    if [[ -n "$NODE_NAME" ]]; then
      GPU_COUNT=$(openshell doctor exec -- \
        kubectl get node "${NODE_NAME}" -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null \
        | tr -d '\r')
      if [[ "$GPU_COUNT" -gt 0 ]] 2>/dev/null; then
        GPU_READY=true
        break
      fi
    fi
  fi

  [[ $((i % 5)) -eq 0 ]] && info "  Still waiting... (${i}/45) ${DP_STATUS:-no pods yet}"
  sleep 2
done

if $GPU_READY; then
  success "nvidia-device-plugin running — ${GPU_COUNT} GPU(s) available ✓"
else
  echo ""
  warn "nvidia-device-plugin did not become ready."
  warn "Diagnostics:"
  openshell doctor exec -- kubectl get pods -n nvidia-device-plugin --no-headers 2>/dev/null \
    | tr -d '\r' | while read -r line; do warn "  $line"; done
  warn ""
  warn "Falling back: creating sandbox WITHOUT --gpu."
  warn "For stable cloud inference, use: ./scripts/wsl2-deploy.sh nvapi-YOUR-KEY"
  warn ""
fi

echo ""

# ============================================================================
# STEP 11: CREATE PROVIDER + SANDBOX
# ============================================================================
info "Step 11/11: Creating provider + sandbox..."

if [[ -n "$API_KEY" ]]; then
  openshell provider create --name nvidia-nim \
    --type openai \
    --credential "OPENAI_API_KEY=${API_KEY}" \
    --config "OPENAI_BASE_URL=https://integrate.api.nvidia.com/v1" 2>/dev/null || true

  openshell inference set --provider nvidia-nim \
    --model nvidia/nemotron-3-super-120b-a12b 2>/dev/null || true

  success "Cloud provider configured ✓"
else
  info "  No API key — skipping cloud provider."
  info "  Tip: pass an API key for cloud inference: ./scripts/wsl2-gpu-deploy.sh nvapi-xxx"
fi

if $GPU_READY; then
  info "Creating GPU-enabled sandbox..."
  SANDBOX_ARGS="--name ${SANDBOX_NAME} --from openclaw --gpu"
else
  info "Creating sandbox without GPU..."
  SANDBOX_ARGS="--name ${SANDBOX_NAME} --from openclaw"
fi

echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  You're about to enter the sandbox. Run these commands:${NC}"
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}# 1. Configure OpenClaw${NC}"
echo "  openclaw onboard"
echo ""
echo -e "  ${BOLD}  When prompted:${NC}"
echo -e "    Model/auth provider → ${BOLD}Custom Provider${NC}"
echo -e "    API Base URL        → ${BOLD}https://inference.local/v1${NC}"
echo -e "    Compatibility       → ${BOLD}OpenAI-compatible${NC}"
echo -e "    Model ID            → ${BOLD}nvidia/nemotron-3-super-120b-a12b${NC}"
echo -e "    Endpoint ID         → ${BOLD}(press Enter for default)${NC}"
echo -e "    Web search          → ${BOLD}(skip)${NC}"
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

if $GPU_READY; then
  echo -e "  ${GREEN}${BOLD}GPU: ${GPU_NAME} (${GPU_MEM} MB) — available inside sandbox${NC}"
  echo -e "  ${GREEN}${BOLD}Run 'nvidia-smi' inside sandbox to verify${NC}"
else
  echo -e "  ${YELLOW}${BOLD}GPU: not available — using cloud inference${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════════════════${NC}"
echo ""
info "Connecting to sandbox now..."
echo ""

# shellcheck disable=SC2086
openshell sandbox create ${SANDBOX_ARGS}
