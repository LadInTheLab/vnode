# Contributing

Contributions welcome. Please follow existing code style, test multi-instance scenarios, and update documentation for changes.

## System Requirements

- Docker 20.10+
- Docker Compose 1.27+ or Compose plugin
- Linux host with MACVLAN support
- WireGuard VPN subscription
- Tailscale account

## Manual Installation

If you prefer manual deployment without the installer:

```bash
# Clone repository
git clone https://github.com/LadInTheLab/vnode.git
cd vnode

# Copy template and edit
cp .env.template .env
nano .env

# Create MACVLAN network
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  pub_net

# Validate and deploy
./scripts/deploy.sh --validate-only
./scripts/deploy.sh
```

## Development

When contributing:

1. Test on actual hardware (not VMs when possible)
2. Verify multi-instance scenarios work correctly
3. Check conflict detection for IPs, MACs, and ports
4. Ensure installer works for both user-local and system-wide installs
5. Test on different Linux distributions if possible
6. Update documentation to reflect any changes

## Code Style

Follow the existing patterns:
- Bash scripts use `set -euo pipefail`
- Functions have descriptive names
- Error handling with clear messages
- Comments explain "why" not "what"
