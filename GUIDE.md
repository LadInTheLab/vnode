# vNode Installation and Configuration Guide

Complete guide for installing, configuring, and using vNode.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [VPN Providers](#vpn-providers)
- [Network Setup](#network-setup)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Installation

### One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/LadInTheLab/vnode/main/install.sh | bash
```

The installer:
- Detects your OS and architecture (Linux, macOS, ARM, x86_64)
- Checks for Docker (offers to install if missing)
- Downloads vNode to appropriate location
- Installs `vnode` CLI command
- Creates configuration directories

**Installation locations:**

User install (default):
- Install: `~/.local/share/vnode`
- Config: `~/.config/vnode`
- Instances: `~/.local/share/vnode/instances`

System install (with sudo):
- Install: `/opt/vnode`
- Config: `/etc/vnode`
- Instances: `/var/lib/vnode/instances`

### Manual Installation

```bash
# Clone repository
git clone https://github.com/LadInTheLab/vnode.git
cd vnode

# Run installer
chmod +x install.sh
./install.sh
```

### Custom Installation Path

```bash
export VNODE_INSTALL_DIR=/opt/my-vnode
export VNODE_INSTANCES_DIR=/data/vnode-instances
./install.sh
```

### Verify Installation

```bash
vnode version
vnode doctor
```

## Quick Start

### Prerequisites

- [ ] Docker 20.10+ installed and running
- [ ] Docker Compose 1.27+ or compose plugin
- [ ] Tailscale account
- [ ] WireGuard VPN subscription
- [ ] Know your network gateway IP (usually 192.168.1.1)

### Create Instance (Wizard)

```bash
vnode create us-east
```

The interactive wizard:
1. Prompts for all required configuration
2. Auto-detects conflicts with existing instances
3. Suggests safe defaults for IPs, MACs, ports
4. Validates configuration
5. Creates MACVLAN network if needed
6. Deploys immediately (optional)

### Start and Monitor

```bash
# Start instance
vnode start us-east

# Check health
vnode health us-east

# Live monitoring dashboard
vnode monitor us-east

# View logs
vnode logs us-east follow
```

### Enable in Tailscale

1. Go to https://login.tailscale.com/admin/machines
2. Find your vNode hostname
3. Click "..." → "Edit route settings"
4. Toggle "Use as exit node"

### Use from Clients

```bash
# Enable exit node
tailscale up --exit-node=us-east

# Verify
curl ifconfig.me  # Should show VPN IP

# Disable
tailscale up --exit-node=
```

## Configuration

### Environment Variables

All configuration is in the `.env` file. The wizard creates this for you, or copy `.env.template` manually.

#### Required: Tailscale

```bash
# Get from: https://login.tailscale.com/admin/settings/keys
TS_AUTHKEY=tskey-auth-XXXXXXXXXXXXXXXXXXXXX

# Hostname for this exit node
TS_HOSTNAME=vnode-us-east
```

**Tips:**
- Use reusable auth keys for automated deployments
- Tag keys (e.g., `tag:exitnode`) for ACL management
- Use descriptive hostnames: `vnode-us-east`, `vnode-eu-west`

#### Required: Network

```bash
# Static IP outside your DHCP range
MACVLAN_IP=192.168.1.200

# Unique MAC address
# Generate: printf 'DE:AD:BE:EF:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256))
MACVLAN_MAC=DE:AD:BE:EF:12:34

# Your router IP
GATEWAY_IP=192.168.1.1

# Docker MACVLAN network name
MACVLAN_NETWORK=pub_net

# Tailscale port (usually don't change)
TUNNEL_PORT=41641
```

**Choosing MACVLAN_IP:**
1. Check your router's DHCP range (e.g., .100-.199)
2. Choose IP outside this range (e.g., .200+)
3. Verify unused: `ping 192.168.1.200`

**Finding Gateway IP:**
```bash
# Linux/macOS
ip route | grep default
# or
netstat -rn | grep default
```

#### Required: VPN

```bash
# Your WireGuard private key
VPN_PRIVATE_KEY=your_wireguard_private_key_here

# VPN server's public key
VPN_PUBLIC_KEY=server_public_key_here

# VPN server IP address
VPN_ENDPOINT_IP=vpn.server.ip.here

# VPN server port (usually 51820)
VPN_PORT=51820

# Your assigned VPN tunnel IP
VPN_IP=10.x.x.x/32
```

See [VPN Providers](#vpn-providers) section for provider-specific instructions.

#### Optional: Tuning

```bash
# DNS server (default: Quad9)
DNS_SERVER=9.9.9.9
# Options: 1.1.1.1 (Cloudflare), 8.8.8.8 (Google), 208.67.222.222 (OpenDNS)

# WireGuard MTU (default: 1280)
WIREGUARD_MTU=1280
# Safe range: 1280-1420

# Keepalive interval in seconds (default: 25)
WIREGUARD_KEEPALIVE=25

# TCP MSS clamping (default: 1120)
# Formula: MTU - 40 (IP) - 20 (TCP)
TCP_MSS_CLAMP=1120

# Health check interval in seconds (default: 300)
HEALTHCHECK_INTERVAL=300

# Update checking
CHECK_UPDATES=true
```

## VPN Providers

### Mullvad

1. Go to https://mullvad.net/account
2. Click "WireGuard configuration"
3. Generate key and select server
4. Download config file

**Extract values from config:**
```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY     → VPN_PRIVATE_KEY
Address = 10.x.x.x/32             → VPN_IP

[Peer]
PublicKey = SERVER_PUBLIC_KEY     → VPN_PUBLIC_KEY
Endpoint = SERVER_IP:51820        → VPN_ENDPOINT_IP (IP part)
                                  → VPN_PORT (port part)
```

### ProtonVPN

1. Go to https://account.protonvpn.com
2. Navigate to Downloads → WireGuard configuration
3. Select server and download config
4. Extract values (same format as Mullvad)

### IVPN

1. Go to https://www.ivpn.net/account
2. Click WireGuard tab
3. Generate key and download config
4. Extract values (same format as Mullvad)

### Other WireGuard Providers

Any VPN provider that offers WireGuard configurations will work. Extract the five required values from the config file.

## Network Setup

### Creating MACVLAN Network

A MACVLAN network gives containers direct IPs on your LAN.

**Basic setup:**
```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  pub_net
```

**Find your network interface:**
```bash
# Linux
ip link show
# Look for: eth0, ens18, enp3s0, etc.

# macOS
ifconfig
# Look for: en0, en1, etc.
```

**With VLAN tagging:**
```bash
# For VLAN 10
docker network create -d macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  -o parent=eth0.10 \
  pub_net
```

**Multiple subnets:**
```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  --aux-address="exclude1=192.168.1.1" \
  --aux-address="exclude2=192.168.1.2" \
  -o parent=eth0 \
  pub_net
```

### Firewall Configuration

Allow outbound connections:
- UDP to VPN server (port from `VPN_PORT`, usually 51820)
- UDP 3478 (STUN for Tailscale)
- UDP 41641 (or your `TUNNEL_PORT`)

**UFW example:**
```bash
sudo ufw allow out 51820/udp
sudo ufw allow out 3478/udp
sudo ufw allow out 41641/udp
```

### Router Configuration

For best performance, configure your router:

1. **Reserve DHCP Range**
   - Configure DHCP to use .100-.199
   - Reserve .200-.254 for static IPs
   - Prevents conflicts with vNode IPs

2. **Port Forwarding** (optional but recommended)
   - Forward UDP port 41641 (or your `TUNNEL_PORT`) to vNode IP
   - Enables direct P2P connections
   - Reduces latency through DERP relays

See [ADVANCED.md](ADVANCED.md) for detailed router instructions.

## Usage

### CLI Commands

```bash
# Instance management
vnode create [name]              # Create new instance
vnode list                       # List all instances
vnode start <name>|all           # Start instance(s)
vnode stop <name>|all            # Stop instance(s)
vnode restart <name>|all         # Restart instance(s)
vnode status [name]              # Show status
vnode delete <name>              # Delete instance

# Monitoring
vnode health [name]              # Health check
vnode monitor <name>             # Live dashboard
vnode ip <name>                  # Show VPN exit IP
vnode logs <name> [follow]       # View logs

# Maintenance
vnode update [name]              # Update containers
vnode check-updates [name]       # Check for updates
vnode shell <name> [container]   # Shell access (gluetun/tailscale)

# Configuration
vnode config <name> [edit]       # View/edit config
vnode validate <name>            # Validate config
vnode info                       # Installation info
vnode doctor                     # System check
```

### Examples

```bash
# Create and start instance
vnode create us-east
vnode start us-east

# Check status of all instances
vnode list
vnode status

# Health check specific instance
vnode health us-east

# Monitor live
vnode monitor us-east

# Update all instances
vnode update all

# Shell access
vnode shell us-east gluetun
```

### Automation

#### Scheduled Health Checks

Add to crontab:
```bash
# Health check every 5 minutes
*/5 * * * * vnode health us-east

# Check for updates daily
0 9 * * * vnode check-updates us-east
```

## Troubleshooting

### Installation Issues

**Docker not found:**
```bash
# The installer offers to install Docker
# Or install manually:
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in
```

**Permission denied:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
docker ps  # Test
```

### Container Issues

**Containers not starting:**
```bash
# Check status
vnode status us-east

# View logs
vnode logs us-east

# Check Docker
vnode doctor
```

**Gluetun not connecting:**
1. Verify VPN credentials in `.env`
2. Check logs: `vnode logs us-east`
3. Try different VPN server
4. Verify VPN account is active

**Tailscale not advertising:**
1. Verify `TS_AUTHKEY` is valid
2. Check logs: `vnode logs us-east`
3. Verify internet connectivity through VPN
4. Enable exit node in Tailscale admin

### Network Issues

**IP conflict:**
```bash
# Choose different IP outside DHCP range
# Edit config
vnode config us-east edit
# Update MACVLAN_IP
# Restart
vnode restart us-east
```

**Can't reach vNode from LAN:**
- Verify MACVLAN network created
- Check firewall rules
- Verify gateway IP is correct

**VPN not connecting:**
- Verify VPN credentials
- Check VPN server is reachable
- Try different VPN endpoint
- Check firewall allows outbound VPN port

### Performance Issues

**High latency:**
1. Adjust MTU: Edit `.env`, set `WIREGUARD_MTU=1280`
2. Try closer VPN server
3. Check CPU usage: `vnode monitor us-east`
4. Configure port forwarding on router

**Connection drops:**
1. Adjust keepalive: Edit `.env`, set `WIREGUARD_KEEPALIVE=25`
2. Check VPN server stability
3. Monitor health: `vnode health us-east`

**MSS/MTU issues:**
1. Lower MTU: `WIREGUARD_MTU=1280`
2. Adjust MSS clamping: `TCP_MSS_CLAMP=1120`
3. Restart instance

### Debugging

**Check container status:**
```bash
vnode status us-east
```

**View detailed logs:**
```bash
vnode logs us-east follow
```

**Shell access:**
```bash
# Gluetun container
vnode shell us-east gluetun

# Inside container, check VPN
wget -qO- https://api.ipify.org

# Tailscale container
vnode shell us-east tailscale

# Inside container, check Tailscale
tailscale status
```

**Health check:**
```bash
vnode health us-east
```

**Validate configuration:**
```bash
vnode validate us-east
```

## Manual Deployment (Power Users)

If you prefer manual deployment without the CLI:

```bash
# Clone repo
git clone https://github.com/LadInTheLab/vnode.git
cd vnode

# Configure
cp .env.template .env
nano .env

# Create network
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  pub_net

# Validate and deploy
./scripts/deploy.sh --validate-only
./scripts/deploy.sh

# Manage manually
docker-compose ps
docker-compose logs -f
docker-compose restart
```

## Next Steps

- **Multi-instance setup**: See [ADVANCED.md](ADVANCED.md) for running multiple vNodes
- **Router configuration**: See [ADVANCED.md](ADVANCED.md) for detailed port forwarding guides
- **Advanced networking**: See [ADVANCED.md](ADVANCED.md) for complex network scenarios
