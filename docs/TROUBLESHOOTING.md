# TNG NemoClaw — Troubleshooting

Every issue below was hit during real testing. These aren't theoretical.

## Quick Diagnostics

```bash
bash scripts/health-check.sh        # Full stack check
openshell status                     # Gateway health
openshell sandbox list               # Running sandboxes
openshell doctor check               # System prerequisites
```

## WSL2: Sandbox "not found" immediately after creation

**Root cause:** `nemoclaw onboard` forces `--gpu` on sandbox creation. GPU passthrough doesn't work on WSL2 + Docker Desktop. The sandbox is dead on arrival.

**Fix:** Use `./scripts/wsl2-deploy.sh` which bypasses `nemoclaw onboard` entirely. See [docs/WSL2-WORKAROUND.md](WSL2-WORKAROUND.md).

## WSL2: "Unit docker.service not found"

**Root cause:** WSL2 doesn't use systemd by default. Docker Desktop manages the daemon from Windows.

**Fix:** Use `sudo service docker start`, not `sudo systemctl start docker`. Our scripts detect WSL2 and handle this.

## WSL2: cgroup v2 / "cgroupns=host" error

**Root cause:** OpenShell's gateway runs k3s inside Docker, which needs `"default-cgroupns-mode": "host"` in Docker's config.

**Fix (Docker Desktop):** Settings → Docker Engine → add `"default-cgroupns-mode": "host"` to JSON → Apply & Restart.

**Fix (native Docker):** `nemoclaw setup-spark` or manually:
```bash
echo '{"default-cgroupns-mode": "host"}' | sudo tee /etc/docker/daemon.json
sudo service docker restart
```

## WSL2: "/etc/docker/daemon.json: No such file or directory"

**Root cause:** Docker Desktop manages daemon config from Windows side. `/etc/docker/` doesn't exist in WSL2.

**Fix:** Set cgroupns in Docker Desktop UI, not from WSL2 command line.

## "Corrupted cluster state" / "K8s namespace not ready"

**Root cause:** Previous failed onboard run left stale k3s state.

**Fix:**
```bash
openshell gateway destroy --name nemoclaw
docker volume rm openshell-cluster-nemoclaw
# Then re-run your deploy script
```

## Port 8080 conflict: "port held by container openshell-cluster-openshell"

**Root cause:** NemoClaw's error messages tell you to run `openshell gateway start` (no `--name`), creating a gateway named "openshell." Then nemoclaw tries "nemoclaw" on the same port.

**Fix:**
```bash
openshell gateway destroy --name openshell
openshell gateway destroy --name nemoclaw
# Then start with consistent name:
openshell gateway start --name nemoclaw
```

## OpenClaw: "Missing gateway auth token"

**Root cause:** The sandbox was created before the inference provider was registered. Credentials are injected at sandbox creation time.

**Fix:** Delete sandbox, ensure provider exists, recreate:
```bash
# From host
openshell provider list              # Verify provider exists
openshell sandbox delete tng-nemoclaw
openshell sandbox create --name tng-nemoclaw --from openclaw
```

## OpenClaw: Still using Anthropic/Claude despite NVIDIA config

**Root cause:** `ANTHROPIC_API_KEY` is set in the environment. OpenClaw sees it and defaults to Claude.

**Fix:** Inside sandbox:
```bash
unset ANTHROPIC_API_KEY
# Run openclaw onboard and select Custom Provider
```

## OpenClaw: "Config validation failed: Unrecognized key"

**Root cause:** OpenClaw's config schema doesn't accept arbitrary keys. Model provider config goes through `openclaw onboard`, not `openclaw config set`.

**Fix:** Run `openclaw onboard` inside the sandbox and use the interactive wizard to set up the provider.

## OpenClaw: "fetch failed" during onboard verification

**Root cause:** The sandbox blocks outbound network. The base URL must be OpenShell's internal proxy, not the external NVIDIA API.

**Fix:** When `openclaw onboard` asks for Base URL, use:
```
https://inference.local/v1
```
NOT `https://integrate.api.nvidia.com/v1`

## Health check dies after first check

**Root cause (fixed in our scripts):** Bash's `((PASS++))` returns exit code 1 when incrementing from 0 (0 is falsy). Combined with `set -e`, the script dies after the first passing check.

**Fix:** We use `PASS=$((PASS + 1))` instead. Already fixed.

## nemoclaw / openshell: "command not found"

```bash
# Add common install locations to PATH
export PATH="$HOME/.local/bin:$PATH"
# For NemoClaw specifically:
cd ~/.tng-nemoclaw/NemoClaw && npm link
```

## macOS: NemoClaw installer warns about Ubuntu

NemoClaw's installer checks for Ubuntu. On macOS, the sandbox runs inside Docker containers (Linux), so this warning is cosmetic. Use `./scripts/macos-deploy.sh` instead of `nemoclaw onboard`.
