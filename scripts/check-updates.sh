#!/bin/bash
#
# check-updates.sh - Check for container image updates
# Usage: ./check-updates.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Images to check
IMAGES=(
    "qmcgaw/gluetun:latest"
    "tailscale/tailscale:latest"
)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Checking for Container Updates${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

updates_available=()

for image in "${IMAGES[@]}"; do
    echo -n "Checking $image... "

    # Get local image digest
    local_digest=$(docker images --no-trunc --format '{{.ID}}' "$image" 2>/dev/null | head -1)

    if [ -z "$local_digest" ]; then
        echo -e "${YELLOW}not found locally${NC}"
        continue
    fi

    # Pull latest digest without downloading
    remote_digest=$(docker manifest inspect "$image" 2>/dev/null | jq -r '.config.digest' 2>/dev/null || echo "")

    if [ -z "$remote_digest" ]; then
        echo -e "${YELLOW}cannot check remote${NC}"
        continue
    fi

    # Compare
    if [ "$local_digest" = "$remote_digest" ]; then
        echo -e "${GREEN}✓ up to date${NC}"
    else
        echo -e "${YELLOW}⚠ update available${NC}"
        updates_available+=("$image")
    fi
done

echo ""

if [ ${#updates_available[@]} -gt 0 ]; then
    echo -e "${YELLOW}Updates available for:${NC}"
    for image in "${updates_available[@]}"; do
        echo -e "  • $image"
    done
    echo ""
    echo "To update, run: vnode update <instance-name>"

    exit 1
else
    echo -e "${GREEN}All containers are up to date!${NC}"
    exit 0
fi
