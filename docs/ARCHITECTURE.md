# TNG NemoClaw — Architecture

## The Stack

```
HOST (macOS / Linux / WSL2)
  ├── openshell CLI ──► manages gateway + sandboxes
  ├── nemoclaw CLI ──► wrapper around openshell (broken on WSL2 --gpu)
  │
  └── Docker Desktop / Engine
       └── OpenShell Gateway Container (k3s cluster)
            ├── Inference proxy (inference.local)
            │   └── Routes to NVIDIA cloud / local NIM / vLLM
            │
            └── Sandbox Container (Landlock + seccomp + netns)
                 ├── OpenClaw agent (Node.js)
                 ├── OpenClaw gateway (port 18789)
                 └── /sandbox/ workspace
```

**Key insight:** Landlock, seccomp, and network namespaces are Linux kernel features. On macOS and WSL2, they work because the sandbox runs inside Docker containers (which run on a Linux VM). The host OS doesn't matter.

## Two Gateways

This confuses everyone. There are TWO separate gateway concepts:

1. **OpenShell Gateway** — the k3s cluster that manages sandboxes, enforces policies, and proxies inference. Runs on the host inside Docker. Managed by `openshell gateway start`.

2. **OpenClaw Gateway** — the AI agent's internal communication server. Runs INSIDE the sandbox on port 18789. Managed by `openclaw gateway run`.

## Inference Flow

```
Agent (inside sandbox)
  → inference.local (OpenShell proxy, inside sandbox network)
  → OpenShell Gateway (host Docker)
  → NVIDIA Cloud API (integrate.api.nvidia.com)
  → Response flows back
```

The sandbox cannot reach the internet directly. All inference goes through OpenShell's proxy. This is why `openclaw onboard` must use `https://inference.local/v1` as the base URL, not the real NVIDIA endpoint.

## Security Layers

| Layer | What it does | Mutable at runtime? |
|-------|-------------|---------------------|
| Network egress | Blocks unauthorized outbound | Yes (hot-reload) |
| Filesystem | Restricts to /sandbox + /tmp | No (locked at creation) |
| Process | Blocks privilege escalation | No (locked at creation) |
| Inference | Routes through controlled proxy | Yes (hot-reload) |

## Credential Injection

OpenShell injects credentials into sandboxes **at creation time** via providers. If you create a provider after the sandbox, the sandbox won't have the credentials. You must delete and recreate the sandbox.

```bash
# Correct order:
openshell provider create ...    # FIRST
openshell sandbox create ...     # THEN
```
