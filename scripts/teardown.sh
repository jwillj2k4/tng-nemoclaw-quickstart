#!/usr/bin/env bash
# ============================================================================
# TNG NemoClaw — Full Teardown
# ============================================================================

set -uo pipefail

INSTALL_DIR="${HOME}/.tng-nemoclaw"

echo ""
echo "TNG NemoClaw — Teardown"
echo ""
read -p "This removes everything. Continue? (y/N): " CONFIRM
[[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]] && echo "Aborted." && exit 0

echo "Stopping sandboxes..."
openshell sandbox delete tng-nemoclaw 2>/dev/null || true
openshell sandbox delete my-assistant 2>/dev/null || true

echo "Destroying gateways..."
openshell gateway destroy --name nemoclaw 2>/dev/null || true
openshell gateway destroy --name openshell 2>/dev/null || true

echo "Removing Docker volumes..."
docker volume rm openshell-cluster-nemoclaw 2>/dev/null || true
docker volume rm openshell-cluster-openshell 2>/dev/null || true

echo "Removing install directory..."
rm -rf "${INSTALL_DIR}"

echo "Removing init helper..."
rm -f "${HOME}/tng-sandbox-init.sh"

echo ""
echo "Done. Docker and Node.js left in place."
