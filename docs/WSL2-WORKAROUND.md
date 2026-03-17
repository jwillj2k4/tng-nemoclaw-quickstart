# WSL2 Workaround: The --gpu Sandbox Bug

## The Problem

NemoClaw v0.0.7 has a confirmed bug that affects **every WSL2 user with an NVIDIA GPU**.

`nemoclaw onboard` checks for `nvidia-smi` during preflight. When it detects a GPU (which it will on WSL2 — nvidia-smi works fine there), it forces `--gpu` on both the gateway start command and sandbox creation. There's no flag to override this.

On WSL2 with Docker Desktop, the GPU is visible to `nvidia-smi` at the WSL2 layer but **cannot be passed through** into the k3s Kubernetes cluster that OpenShell runs inside the Docker container. The result:

1. `openshell gateway start --name nemoclaw --gpu` → starts, but GPU is not allocatable
2. `openshell sandbox create --gpu ...` → GPU allocation fails
3. Sandbox reports "created" but is immediately dead
4. Every subsequent command returns `"sandbox not found"`
5. Even if you rebuild, the same cycle repeats

The "✓ Sandbox created" message is a false positive. The sandbox is DOA.

## Who's Affected

Everyone on WSL2 with any NVIDIA GPU:
- RTX 5090 (confirmed)
- RTX 5070 Ti ([confirmed by other users](https://forums.developer.nvidia.com/t/363769))
- RTX 40 series ([confirmed](https://github.com/NVIDIA/NemoClaw/issues/140))
- Likely all NVIDIA GPUs on WSL2

## Root Cause (Deep)

Investigation by [@tyeth-ai-assisted](https://github.com/NVIDIA/OpenShell/issues/404) identified three cascading failures:

**1. No native NVIDIA device nodes.** WSL2 virtualises GPU access through `/dev/dxg` (DirectX GPU abstraction) instead of exposing `/dev/nvidia*` device nodes. `nvidia-smi` works at the WSL2 layer via the driver shim, but the nvidia container runtime's legacy injection path fails inside k3s pods.

**2. NFD cannot detect NVIDIA PCI device.** WSL2 does not expose PCI topology to the guest kernel. Node Feature Discovery only sees Microsoft Hyper-V (`pci-1414`), never NVIDIA (`pci-10de`). The nvidia-device-plugin DaemonSet's node affinity is never satisfied — 0 desired replicas.

**3. Missing libdxcore.so in CDI spec.** Even when the DaemonSet is forced to schedule, the device plugin crashes with `Failed to initialize NVML: Not Supported`. The nvidia runtime's `auto` mode uses legacy injection which doesn't mount `libdxcore.so` — the critical library bridging Linux NVML to the Windows DirectX GPU Kernel via `/dev/dxg`.

**Failure chain:**
```
WSL2 /dev/dxg (not /dev/nvidia*)
  → NFD can't see PCI vendor 10de
    → Node never gets pci-10de.present label
      → nvidia-device-plugin DaemonSet: 0 pods

Even when forced to schedule:
  → nvidia runtime auto mode uses legacy injection
    → libdxcore.so not injected into pods
      → NVML init fails: "Not Supported"
        → device plugin crashes, no nvidia.com/gpu resource
```

**Upstream issues:**
- OpenShell: [NVIDIA/OpenShell#404](https://github.com/NVIDIA/OpenShell/issues/404)
- nvidia-container-toolkit: [NVIDIA/nvidia-container-toolkit#1739](https://github.com/NVIDIA/nvidia-container-toolkit/issues/1739)
- NemoClaw: [NVIDIA/NemoClaw#208](https://github.com/NVIDIA/NemoClaw/issues/208)

## Two Paths: Choose Your Approach

### Path A: Skip GPU, Use Cloud Inference (Stable)

**Best for:** Getting started fast, cloud inference is fine, don't want to fight GPU plumbing.

**Script:** `./scripts/wsl2-deploy.sh nvapi-YOUR-KEY`

Bypasses `nemoclaw onboard` entirely. Starts gateway WITHOUT `--gpu`. Sandbox uses cloud inference via OpenShell's proxy at `inference.local`. Requires an NVIDIA API key (free at [build.nvidia.com](https://build.nvidia.com)).

### Path B: Patch CDI, Enable Local GPU (Experimental — Confirmed Working)

**Best for:** Local inference, no cloud dependency, full privacy story, you have a beefy GPU.

**Confirmed on:** RTX 5090 Laptop (24GB), WSL2 Ubuntu 24.04, Docker Desktop, OpenShell 0.0.7.

**Script:** `./scripts/wsl2-gpu-deploy.sh [optional-api-key]`

Starts gateway WITH `--gpu`, then patches the CDI pipeline so the nvidia device plugin can actually see the GPU. API key is optional — this path enables local inference. If provided, cloud inference is configured as a fallback.

**What the script does:**
1. Generates CDI spec with `nvidia-ctk cdi generate` (auto-detects WSL mode)
2. Discovers GPU UUID and adds it as a named CDI device (k8s allocates by UUID, not by `all`)
3. Patches the CDI spec to include `libdxcore.so` mount and ldcache folder
4. Copies spec to `/etc/cdi/` for containerd
5. Switches nvidia runtime from `auto` to `cdi` mode
6. Enables `enable_cdi = true` in containerd's k3s config
7. Restarts containerd to pick up all CDI/runtime changes
8. Labels the k3s node with `pci-10de.present=true` for DaemonSet scheduling
9. Force-deletes nvidia pods so they reschedule with new CDI config
10. Waits for `nvidia-device-plugin` to reach Running with GPU capacity
11. Creates provider (--type openai) and GPU-enabled sandbox
12. Falls back to no-GPU sandbox if device plugin doesn't come up

**If it fails:** The script automatically falls back to creating a sandbox without `--gpu`. You can also manually fall back to Path A at any time.

---

## Path A: Detailed Steps

### Host-side (automated by script)

```bash
# 1. Clean slate — stale gateways from previous failed runs WILL corrupt state
openshell sandbox delete tng-nemoclaw 2>/dev/null
openshell gateway destroy --name nemoclaw 2>/dev/null
docker volume rm openshell-cluster-nemoclaw 2>/dev/null

# 2. Start gateway WITHOUT --gpu — this is the key fix
openshell gateway start --name nemoclaw

# 3. Create NVIDIA inference provider BEFORE the sandbox
#    (credentials are injected at sandbox creation time)
openshell provider create --name nvidia-nim --type nvidia \
  --credential NVIDIA_API_KEY=nvapi-your-key

# 4. Set inference route through OpenShell's proxy
openshell inference set --provider nvidia-nim \
  --model nvidia/nemotron-3-super-120b-a12b

# 5. Create sandbox WITHOUT --gpu — this one stays alive
openshell sandbox create --name tng-nemoclaw --from openclaw
```

### Sandbox-side (manual — interactive wizard)

Once inside the sandbox, you need to configure OpenClaw's model provider. The critical insight: the sandbox **cannot reach the internet directly** (that's the whole point of the sandbox). Inference must route through OpenShell's proxy at `https://inference.local/v1`.

```bash
# Run OpenClaw's own setup wizard
openclaw onboard
```

When prompted:
- **Model/auth provider:** Custom Provider
- **API Base URL:** `https://inference.local/v1`
- **Endpoint compatibility:** OpenAI-compatible
- **Model ID:** `nvidia/nemotron-3-super-120b-a12b`
- **Endpoint ID:** (press Enter for default)
- **Web search:** (skip)

Then start the OpenClaw gateway and chat interface:

```bash
mkdir -p /sandbox/.openclaw/workspace/memory
echo "# Memory" > /sandbox/.openclaw/workspace/MEMORY.md
openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true
nohup openclaw gateway run --allow-unconfigured --dev --bind loopback --port 18789 > /tmp/gateway.log 2>&1 &
sleep 5
openclaw tui
```

---

## Path B: Detailed Steps

### Host-side (automated by script)

```bash
# 1. Clean slate
openshell sandbox delete tng-nemoclaw 2>/dev/null
openshell gateway destroy --name nemoclaw 2>/dev/null
docker volume rm openshell-cluster-nemoclaw 2>/dev/null

# 2. Start gateway WITH --gpu
openshell gateway start --name nemoclaw --gpu

# 3. Wait for core pods, then patch CDI
openshell doctor exec -- nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml

# 4. Patch libdxcore.so into CDI spec (see wsl2-gpu-deploy.sh for full YAML patch)
# The nvidia-ctk logs "Could not locate libdxcore.so" but it IS present at:
#   /usr/lib/x86_64-linux-gnu/libdxcore.so

# 5. Switch runtime to CDI mode
openshell doctor exec -- \
  sed -i 's/mode = "auto"/mode = "cdi"/' /etc/nvidia-container-runtime/config.toml

# 6. Label node for device plugin scheduling
NODE=$(openshell doctor exec -- kubectl get nodes --no-headers -o custom-columns=":metadata.name" | head -1)
openshell doctor exec -- kubectl label node "$NODE" \
  feature.node.kubernetes.io/pci-10de.present=true --overwrite

# 7. Wait for nvidia-device-plugin to show 1/1 Running
# 8. Verify: nvidia.com/gpu: 1 in node capacity

# 9. Create GPU-enabled sandbox
openshell sandbox create --name tng-nemoclaw --from openclaw --gpu
```

### Sandbox-side

Same as Path A — run `openclaw onboard` with Custom Provider → `inference.local`.

---

## Common Issues

### Why nemoclaw onboard Can't Be Fixed From Outside

The `--gpu` flag is hardcoded in NemoClaw's TypeScript onboard wizard based on GPU detection. There's no `--no-gpu` flag, no env var to skip it, and no config option. The only fix is a code change in `nemoclaw onboard` to make GPU passthrough optional. See [PR #209](https://github.com/NVIDIA/NemoClaw/pull/209).

### Stale Gateway Corruption

Every failed `nemoclaw onboard` run leaves corrupted gateway state. If you see "Corrupted cluster state" or "K8s namespace not ready," you must:

```bash
openshell gateway destroy --name nemoclaw
docker volume rm openshell-cluster-nemoclaw
```

Both deploy scripts do this automatically at the start.

### Port Conflict: gateway name "openshell" vs "nemoclaw"

NemoClaw's error messages tell you to run `openshell gateway start` (no `--name`), which creates a gateway named "openshell" on port 8080. Then `nemoclaw onboard` tries to create a second gateway named "nemoclaw" on the same port. Always use `--name nemoclaw` consistently.

### Environment Variable Pitfall

If `ANTHROPIC_API_KEY` is set in the sandbox environment, OpenClaw will default to Anthropic Claude regardless of your model config. **Never set `ANTHROPIC_API_KEY`** inside the sandbox unless you actually want to use Claude.

## Credits

Root cause analysis of the WSL2 GPU/CDI failure chain by [@tyeth-ai-assisted](https://github.com/tyeth-ai-assisted) ([OpenShell#404](https://github.com/NVIDIA/OpenShell/issues/404)). Original bug report and NemoClaw-layer fix by [@mattezell](https://github.com/mattezell) ([NemoClaw#208](https://github.com/NVIDIA/NemoClaw/issues/208), [PR#209](https://github.com/NVIDIA/NemoClaw/pull/209)).
