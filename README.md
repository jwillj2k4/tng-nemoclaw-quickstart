# 🛡️ TNG NemoClaw Quickstart

**Ship your first secure AI agent in under 30 minutes.**

Built by [The New Guard](https://thenewguard.ai) — the newsletter for builders who want to stay ahead of the AI curve.

---

## What This Is

A batteries-included starter kit for [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) — the open-source security stack that wraps OpenClaw agents in enterprise-grade sandboxing, policy enforcement, and inference routing.

## ⚠️ Known Issue: WSL2 + GPU

**NemoClaw v0.0.7 has a confirmed bug on WSL2 with NVIDIA GPUs.** The `nemoclaw onboard` wizard forces `--gpu` on gateway and sandbox creation when it detects an NVIDIA GPU via `nvidia-smi`. On WSL2 with Docker Desktop, the GPU can't be passed through to the k3s cluster inside the gateway container, so every sandbox is dead on arrival.

**This repo includes a full workaround** — see [Quick Start](#quick-start) below or [docs/WSL2-WORKAROUND.md](docs/WSL2-WORKAROUND.md) for the deep explanation.

This affects everyone on WSL2 with an NVIDIA GPU. [Others have reported the same issue.](https://forums.developer.nvidia.com/t/bug-rtx-5070-ti-sandbox-notfound-access-denied-on-nemoclaw-onboarding-wsl2/363769)

---

## Quick Start

### WSL2 (with or without NVIDIA GPU)

```bash
git clone https://github.com/YOUR_ORG/tng-nemoclaw-quickstart.git
cd tng-nemoclaw-quickstart

# Phase 1: Install CLIs (one-time)
chmod +x scripts/*.sh setup.sh
./setup.sh

# Phase 2: Deploy (bypasses nemoclaw onboard --gpu bug)
# Get a free NVIDIA API key at https://build.nvidia.com first
./scripts/wsl2-deploy.sh nvapi-YOUR-KEY-HERE
```

### macOS (Docker Desktop)

```bash
git clone https://github.com/YOUR_ORG/tng-nemoclaw-quickstart.git
cd tng-nemoclaw-quickstart
chmod +x scripts/*.sh setup.sh
./setup.sh
./scripts/macos-deploy.sh nvapi-YOUR-KEY-HERE
```

### Native Linux (no GPU issues)

```bash
git clone https://github.com/YOUR_ORG/tng-nemoclaw-quickstart.git
cd tng-nemoclaw-quickstart
chmod +x scripts/*.sh setup.sh
./setup.sh
# On native Linux with NVIDIA Container Toolkit, nemoclaw onboard works:
cd ~/.tng-nemoclaw/NemoClaw && nemoclaw onboard
```

---

## How It Works

The setup is split into two phases:

**Phase 1 (`setup.sh`):** Installs prerequisites (Docker, Node.js, Git), clones OpenShell + NemoClaw repos, installs both CLIs, copies TNG policy templates. Works on all platforms.

**Phase 2 (platform-specific deploy):** Creates the OpenShell gateway, inference provider, sandbox, and configures OpenClaw inside the sandbox. On WSL2/macOS, this bypasses `nemoclaw onboard` entirely because of the `--gpu` bug.

---

## What's Inside

```
tng-nemoclaw-quickstart/
├── setup.sh                        # Phase 1: Install CLIs + policies
├── scripts/
│   ├── install-prereqs.sh          # Docker, Node.js, Git (cross-platform)
│   ├── deploy-nemoclaw.sh          # Install OpenShell + NemoClaw CLIs
│   ├── wsl2-deploy.sh              # Phase 2: WSL2 full deploy (workaround)
│   ├── macos-deploy.sh             # Phase 2: macOS full deploy (workaround)
│   ├── health-check.sh             # Verify the full stack
│   └── teardown.sh                 # Clean uninstall
├── policies/                       # OpenShell YAML security policies
│   ├── base/default-lockdown.yaml  # Maximum restriction baseline
│   ├── healthcare/hipaa-agent.yaml # HIPAA-compliant
│   ├── financial/soc2-agent.yaml   # SOC 2 auditable
│   ├── legal/legal-privilege.yaml  # Attorney-client privilege
│   └── dev/permissive-dev.yaml     # Development/testing
├── agents/                         # Pre-configured agent examples
├── monitoring/                     # Loki + Promtail + Grafana stack
├── blueprints/                     # Single and multi-agent deployment
├── examples/                       # Custom skill + inference profiles
└── docs/
    ├── WSL2-WORKAROUND.md          # The GPU bug explained + full fix
    ├── ARCHITECTURE.md             # Stack walkthrough
    ├── POLICIES.md                 # Policy writing guide
    ├── TROUBLESHOOTING.md          # Every issue we hit, solved
    └── OPPORTUNITIES.md            # Where the money is
```

---

## Requirements

| | macOS | Linux | WSL2 |
|---|---|---|---|
| **OS** | macOS 13+ | Ubuntu 22.04+ | Ubuntu 22.04+ on Windows |
| **Docker** | Docker Desktop | Docker Engine or Desktop | Docker Desktop + WSL integration |
| **RAM** | 16GB+ | 16GB+ | 16GB+ |
| **NVIDIA API Key** | Required | Required | Required |
| **GPU** | N/A | Optional (local inference) | Detected but not usable (known bug) |

Get a free NVIDIA API key at [build.nvidia.com](https://build.nvidia.com).

---

## Contributing

PRs welcome — especially new vertical policy templates, platform-specific fixes, and agent blueprints.

## License

Apache 2.0 — same as NemoClaw itself.

## Credits

Built by [The New Guard](https://thenewguard.ai). NemoClaw and OpenShell are NVIDIA open-source projects under Apache 2.0. **Not affiliated with NVIDIA.**
