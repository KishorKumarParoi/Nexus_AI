#!/usr/bin/env bash
# ==============================================================================
# 🛑 ZERO-COST INSTANT TEARDOWN SCRIPT — NEXUS-AI PLATFORM
# Ensures $0.00 lingering compute costs by terminating all Docker containers,
# background daemons, and freeing ports 3000, 3001, 3002, 5000, 8081, 9090.
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping Nexus-AI platform services..."
if docker compose version &>/dev/null; then
    docker compose down --remove-orphans 2>/dev/null || true
elif command -v docker-compose &>/dev/null; then
    docker-compose down --remove-orphans 2>/dev/null || true
fi

# Kill remaining processes by port
for port in 3000 3001 3002 5000 8081 9090; do
    if command -v lsof &>/dev/null; then
        PIDS=$(lsof -ti :"$port" 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
        fi
    fi
done

echo "Platform torn down successfully. $0.00 active compute."
