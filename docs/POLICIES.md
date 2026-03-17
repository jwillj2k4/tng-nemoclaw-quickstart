# TNG NemoClaw — Policy Writing Guide

## The Basics

OpenShell policies are YAML files controlling network, filesystem, and inference routing. Start with `policies/base/default-lockdown.yaml` and open only what you need.

## Applying a Policy

```bash
# From the host (not inside sandbox)
openshell policy set --policy policies/base/default-lockdown.yaml

# Network policies are hot-reloadable — no restart needed
# Filesystem and process policies are locked at sandbox creation
```

## Available Templates

| Template | Use Case | Cloud Inference? |
|----------|----------|-----------------|
| `base/default-lockdown.yaml` | Maximum restriction baseline | Yes (NVIDIA only) |
| `healthcare/hipaa-agent.yaml` | HIPAA Technical Safeguards | No (local only) |
| `financial/soc2-agent.yaml` | SOC 2 audit trail | Yes (with redaction) |
| `legal/legal-privilege.yaml` | Attorney-client privilege | No (local only) |
| `dev/permissive-dev.yaml` | Development/testing | Yes (broad access) |

## Writing Your Own

1. Deploy with `dev/permissive-dev.yaml` (broad + logged)
2. Run your agent through real tasks
3. Review logs to see what it reaches
4. Build your production policy from observed behavior
5. Test the restrictive policy
6. Deploy

See [OPPORTUNITIES.md](OPPORTUNITIES.md) for the consulting opportunity here.
