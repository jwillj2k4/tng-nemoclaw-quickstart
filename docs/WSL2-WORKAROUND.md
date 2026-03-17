# WSL2 Workaround: The --gpu Sandbox Bug

## The Problem

NemoClaw v0.0.7 has a confirmed bug that affects **every WSL2 user with an NVIDIA GPU**.

`nemoclaw onboard` checks for `nvidia-smi` during preflight. When it detects a GPU (which it will on WSL2 — nvidia-smi works fine there), it forces `--gpu` on both the gateway start command and sandbox creation. There's no flag to override this.

On WSL2 with Docker Desktop, the GPU is visible to `nvidia-smi` at the WSL2 layer but **cannot be passed through** into the k3s Kubernetes cluster that OpenShell runs inside the Docker container. The result:

1. `openshell gateway start --name nemoclaw --gpu` → fails or starts without GPU
2. `openshell sandbox create --gpu ...` → GPU allocation fails
3. Sandbox reports "created" but is immediately dead
4. Every subsequent command returns `"sandbox not found"`
5. Even if you rebuild, the same cycle repeats

The "✓ Sandbox created" message is a false positive. The sandbox is DOA.

## Who's Affected

Everyone on WSL2 with any NVIDIA GPU:
- RTX 5090 (confirmed)
- RTX 5070 Ti ([confirmed by other users](https://forums.developer.nvidia.com/t/363769))
- Likely all RTX cards on WSL2

macOS with Docker Desktop may have the same issue if NVIDIA drivers were to be present.

## The Solution

**Bypass `nemoclaw onboard` entirely** and drive `openshell` directly without `--gpu`.

Our `wsl2-deploy.sh` script automates the host-side setup. Here's what it does and why:

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

## Why nemoclaw onboard Can't Be Fixed From Outside

The `--gpu` flag is hardcoded in NemoClaw's TypeScript onboard wizard based on GPU detection. There's no `--no-gpu` flag, no env var to skip it, and no config option. The only fix is a code change in `nemoclaw onboard` to make GPU passthrough optional. We recommend filing an issue on [github.com/NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw/issues).

## Stale Gateway Corruption

Every failed `nemoclaw onboard` run leaves corrupted gateway state. If you see "Corrupted cluster state" or "K8s namespace not ready," you must:

```bash
openshell gateway destroy --name nemoclaw
docker volume rm openshell-cluster-nemoclaw
```

The `wsl2-deploy.sh` script does this automatically at the start.

## Port Conflict: gateway name "openshell" vs "nemoclaw"

NemoClaw's error messages tell you to run `openshell gateway start` (no `--name`), which creates a gateway named "openshell" on port 8080. Then `nemoclaw onboard` tries to create a second gateway named "nemoclaw" on the same port. Always use `--name nemoclaw` consistently.

## Environment Variable Pitfall

If `ANTHROPIC_API_KEY` is set in the sandbox environment, OpenClaw will default to Anthropic Claude regardless of your model config. **Never set `ANTHROPIC_API_KEY`** inside the sandbox unless you actually want to use Claude.
