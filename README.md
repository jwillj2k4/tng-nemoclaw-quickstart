# 🛡️ TNG NemoClaw Quickstart

**Ship your first secure AI agent in under 30 minutes.**

Built by [The New Guard](https://thenewguard.ai) — the newsletter for builders who want to stay ahead of the AI curve.

---

## What This Is

A batteries-included starter kit for [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) — the open-source security stack that wraps OpenClaw agents in enterprise-grade sandboxing, policy enforcement, and inference routing.

This repo gives you:

- **`setup.sh`** — One-command automated deployment (prereqs → OpenShell → NemoClaw → running agent)
- **Production-ready security policies** — HIPAA, SOC 2, financial, legal, and dev/testing templates
- **Pre-configured agent blueprints** — Research, code review, and data analysis agents ready to customize
- **Monitoring scaffolding** — Docker Compose stack with log aggregation and alert rules
- **Vertical opportunity examples** — See where the money is and start building

## Why This Exists

OpenClaw became the fastest-growing open-source project in history. It also had 20% of its plugin marketplace distributing malware, 135,000+ instances exposed to the internet with no auth, and a one-click RCE that let any website hijack your agent.

NemoClaw fixes that. But the docs are early, the tooling is alpha, and most builders haven't touched it yet.

**This repo is your head start.**

---

## Quick Start

```bash
git clone https://github.com/thenewguardai/tng-nemoclaw-quickstart
cd tng-nemoclaw-quickstart
chmod +x setup.sh
./setup.sh
```

That's it. The script handles prerequisites, installs OpenShell and NemoClaw, deploys a sandboxed agent with the default lockdown policy, and drops you into a connected session.

### What `setup.sh` Does (Under the Hood)

1. Checks and installs prerequisites (Docker, Git, Node.js)
2. Clones and builds NVIDIA OpenShell
3. Clones NemoClaw and runs the installer
4. Copies TNG policy templates into the deployment
5. Runs a health check to verify everything's live
6. Connects you to your first sandboxed agent

### Manual Setup

If you prefer to go step-by-step, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full walkthrough.

---

## Repo Structure

```
tng-nemoclaw-quickstart/
├── setup.sh                    # One-command deployment
├── scripts/
│   ├── install-prereqs.sh      # Docker, Node.js, system deps
│   ├── deploy-nemoclaw.sh      # NemoClaw + OpenShell install
│   ├── health-check.sh         # Verify the full stack
│   └── teardown.sh             # Clean uninstall
├── policies/                   # OpenShell YAML security policies
│   ├── base/                   # Strict default lockdown
│   ├── healthcare/             # HIPAA-compliant agent policies
│   ├── financial/              # SOC 2 / financial compliance
│   ├── legal/                  # Legal privilege & data isolation
│   └── dev/                    # Permissive dev/testing policy
├── agents/                     # Pre-configured agent examples
│   ├── research-agent/         # Web research with source tracking
│   ├── code-review-agent/      # Sandboxed code analysis
│   └── data-analyst-agent/     # CSV/data processing in isolation
├── monitoring/                 # Observability stack
│   ├── docker-compose.yaml     # Loki + Promtail + Grafana
│   ├── dashboards/             # Pre-built Grafana dashboards
│   └── alerts/                 # Alert rules for policy violations
├── blueprints/                 # NemoClaw deployment blueprints
│   ├── single_agent.py         # Single sandboxed agent
│   └── multi_agent.py          # Multi-agent orchestration
├── examples/
│   ├── custom-skill/           # Write a safe, auditable skill
│   └── inference-profiles/     # Switch between cloud/local/vLLM
└── docs/
    ├── ARCHITECTURE.md         # Full stack walkthrough
    ├── POLICIES.md             # Policy writing guide
    ├── TROUBLESHOOTING.md      # Known issues & fixes
    └── OPPORTUNITIES.md        # Where the money is
```

---

## Policy Templates

Every enterprise deployment needs custom security policies. We ship five starting points:

| Policy | Use Case | Network | Filesystem | Inference |
|--------|----------|---------|------------|-----------|
| `base/default-lockdown.yaml` | Maximum restriction baseline | Deny all except inference | `/sandbox` + `/tmp` only | Cloud API only |
| `healthcare/hipaa-agent.yaml` | HIPAA-compliant deployments | Allowlisted EHR endpoints | PHI isolation boundaries | Local NIM only (no cloud) |
| `financial/soc2-agent.yaml` | SOC 2 auditable pipelines | Financial data APIs only | Audit trail on all writes | Configurable |
| `legal/legal-privilege.yaml` | Attorney-client privilege | Internal systems only | Strict read/write logging | Local only |
| `dev/permissive-dev.yaml` | Development & testing | Broad (with logging) | Full sandbox access | Any profile |

See [docs/POLICIES.md](docs/POLICIES.md) for how to write your own.

---

## Requirements

- **OS:** Ubuntu 22.04 LTS or later
- **RAM:** 16GB minimum (32GB+ recommended for local inference)
- **Docker:** Installed and running
- **NVIDIA API Key:** Free tier at [build.nvidia.com](https://build.nvidia.com) (for cloud inference)
- **GPU (optional):** NVIDIA GPU for local Nemotron inference via vLLM

---

## Contributing

This is a community resource. PRs welcome — especially:

- New vertical policy templates (insurance, government, education)
- Agent blueprints for specific use cases
- Monitoring improvements and dashboard templates
- Bug fixes and platform compatibility patches

---

## License

Apache 2.0 — same as NemoClaw itself.

---

## Credits

Built by [The New Guard](https://thenewguard.ai). NemoClaw and OpenShell are NVIDIA open-source projects under Apache 2.0.

**Not affiliated with NVIDIA.** This is an independent community resource for builders.
