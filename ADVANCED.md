# Advanced Topics

Multi-instance deployment, networking, and router configuration for vNode.

## Table of Contents

- [Multi-Instance Deployment](#multi-instance-deployment)
- [Router Configuration](#router-configuration)
- [Advanced Networking](#advanced-networking)

## Multi-Instance Deployment

Deploy multiple vNodes on the same host for different locations or VPN providers.

### Why Multiple Instances?

- **Multiple locations**: Exit nodes in different geographic regions
- **Multiple VPN providers**: Different services for different purposes
- **Load distribution**: Spread traffic across multiple exit nodes
- **Redundancy**: Fallback options if one VPN has issues

### Unique Requirements

Each instance **MUST** have unique:

1. **MACVLAN_IP** - Different IP address on your LAN
2. **MACVLAN_MAC** - Different MAC address
3. **TUNNEL_PORT** - Different Tailscale tunnel port
4. **TS_HOSTNAME** - Different Tailscale hostname

### Quick Multi-Instance Setup

Using the CLI (recommended):

```bash
# Create first instance
vnode create us-east

# Create second instance
vnode create eu-west
# Wizard auto-detects us-east and suggests unique values

# Create third instance
vnode create ap-south
# Wizard detects both existing instances
```

The wizard automatically:
- Scans for existing instances
- Detects used IPs, MACs, ports
- Suggests next available values
- Validates no conflicts exist

### Manual Multi-Instance Setup

If deploying manually:

**Instance 1** (us-east):
```bash
TS_HOSTNAME=vnode-us-east
MACVLAN_IP=192.168.1.200
MACVLAN_MAC=DE:AD:BE:EF:12:34
TUNNEL_PORT=41641
```

**Instance 2** (eu-west):
```bash
TS_HOSTNAME=vnode-eu-west
MACVLAN_IP=192.168.1.201      # Different IP
MACVLAN_MAC=DE:AD:BE:EF:56:78 # Different MAC
TUNNEL_PORT=41642             # Different port
```

**Instance 3** (ap-south):
```bash
TS_HOSTNAME=vnode-ap-south
MACVLAN_IP=192.168.1.202      # Different IP
MACVLAN_MAC=DE:AD:BE:EF:9A:BC # Different MAC
TUNNEL_PORT=41643             # Different port
```

### Network Planning

#### IP Address Allocation

Reserve a range for vNodes outside your DHCP range:

```
Router:            192.168.1.1
DHCP Range:        192.168.1.100 - 192.168.1.199
vNode Range:       192.168.1.200 - 192.168.1.254

vnode-us-east:     192.168.1.200
vnode-eu-west:     192.168.1.201
vnode-ap-south:    192.168.1.202
```

**Document your allocation:**
```bash
cat > IP_ALLOCATION.txt << EOF
vNode IP Allocation
===================
192.168.1.200 - vnode-us-east    (Mullvad US)
192.168.1.201 - vnode-eu-west    (ProtonVPN EU)
192.168.1.202 - vnode-ap-south   (IVPN Singapore)
EOF
```

#### Port Allocation

Default Tailscale tunnel ports start at 41641:

```
Instance 1: 41641
Instance 2: 41642
Instance 3: 41643
```

#### MAC Address Generation

Generate unique MACs:

```bash
# Generate 5 unique MACs
for i in {1..5}; do
    printf "Instance $i: DE:AD:BE:EF:%02X:%02X\n" $((RANDOM%256)) $((RANDOM%256))
done
```

### Managing Multiple Instances

```bash
# List all instances
vnode list

# Start all instances
vnode start all

# Stop all instances
vnode stop all

# Health check all instances
vnode health

# Update all instances
vnode update all

# Specific instance operations
vnode start us-east
vnode health eu-west
vnode monitor ap-south
```

### Conflict Detection

The system automatically detects conflicts:

```bash
# When deploying, checks for:
- IP address conflicts (MACVLAN_IP)
- MAC address conflicts (MACVLAN_MAC)
- Port conflicts (TUNNEL_PORT)
```

**Example conflict output:**
```
[✗] Detected conflicts with other vNode instances:
  • IP 192.168.1.200 is used by instance at /home/user/.local/share/vnode/instances/us-east
  • Port 41641 is used by us-east

Run: vnode validate <instance>
```

**Resolution:**
```bash
# Use wizard to reconfigure
cd ~/.local/share/vnode/instances/eu-west
./scripts/setup-wizard.sh

# Or edit config manually
vnode config eu-west edit
```

## Router Configuration

After deployment, configure your router for optimal performance.

### 1. DHCP Range Configuration (Critical)

**Why**: Prevents IP conflicts between DHCP-assigned addresses and your vNode's static IP.

#### What You Need

From your `.env`:
- **MACVLAN_IP**: Your vNode's static IP (e.g., 192.168.1.200)

#### Configure DHCP Range

**Rule:** DHCP must NOT include your vNode IP(s).

**Example:**
```
vNode IP:        192.168.1.200
DHCP Range:      192.168.1.100 - 192.168.1.199
                                 ^ Must be BEFORE vNode IP
```

**Multiple vNodes:**
```
vNodes:          192.168.1.200, .201, .202
DHCP Range:      192.168.1.100 - 192.168.1.199
                 All vNodes are safely above DHCP range
```

#### Router-Specific Instructions

**TP-Link:**
```
Advanced → Network → DHCP Server
  Start IP:  192.168.1.100
  End IP:    192.168.1.199
  Save
```

**Netgear:**
```
Advanced → Setup → LAN Setup
  Starting IP:  192.168.1.100
  Ending IP:    192.168.1.199
  Apply
```

**Linksys:**
```
Connectivity → Local Network → DHCP Server
  Start IP:  192.168.1.100
  End IP:    192.168.1.199
  Save
```

**ASUS:**
```
LAN → DHCP Server
  IP Pool Starting Address:  192.168.1.100
  IP Pool Ending Address:    192.168.1.199
  Apply
```

**UniFi Dream Machine:**
```
Settings → Networks → Default → Edit
  Advanced → DHCP Mode: DHCP Server
  DHCP Range: 192.168.1.100 - 192.168.1.199
  Apply Changes
```

**pfSense / OPNsense:**
```
Services → DHCP Server → LAN
  Range:
    From: 192.168.1.100
    To:   192.168.1.199
  Save
```

#### Verification

```bash
# Before deployment - should timeout
ping 192.168.1.200

# After deployment - should respond
ping 192.168.1.200
```

### 2. Port Forwarding (Recommended)

**Why**: Enables direct P2P connections instead of routing through Tailscale DERP relays.

**Benefits:**
- Lower latency
- Higher throughput
- Better reliability
- Full speed connections

**Without port forwarding:**
- Works but uses DERP relays
- Higher latency
- Lower throughput

#### What You Need

From your `.env`:
- **TUNNEL_PORT**: External port (default: 41641)
- **MACVLAN_IP**: Internal IP (e.g., 192.168.1.200)

#### Port Forwarding Rule

**Single instance:**
```
Service Name:    vNode Tailscale
Protocol:        UDP (not TCP!)
External Port:   41641
Internal IP:     192.168.1.200
Internal Port:   41641
```

**Multiple instances:**
```
Instance 1 (us-east):
  Port: 41641 → 192.168.1.200:41641

Instance 2 (eu-west):
  Port: 41642 → 192.168.1.201:41642

Instance 3 (ap-south):
  Port: 41643 → 192.168.1.202:41643
```

#### Router-Specific Instructions

**TP-Link:**
```
Advanced → NAT Forwarding → Virtual Servers → Add
  Service Type:    Custom
  External Port:   41641
  Internal IP:     192.168.1.200
  Internal Port:   41641
  Protocol:        UDP
  Status:          Enabled
  Save
```

**Netgear:**
```
Advanced → Advanced Setup → Port Forwarding/Triggering
  Service Name:    vNode
  External Port:   41641
  Internal IP:     192.168.1.200
  Internal Port:   41641
  Protocol:        UDP
  Apply
```

**Linksys:**
```
Security → Apps and Gaming → Single Port Forwarding
  Application Name:  vNode
  External Port:     41641
  Internal Port:     41641
  Protocol:          UDP
  Device IP:         192.168.1.200
  Enabled:           ✓
  Save
```

**ASUS:**
```
WAN → Virtual Server / Port Forwarding → Add
  Service Name:    vNode
  Port Range:      41641
  Local IP:        192.168.1.200
  Local Port:      41641
  Protocol:        UDP
  Apply
```

**UniFi Dream Machine:**
```
Settings → Routing → Port Forwarding → Create Entry
  Name:            vNode-Tailscale
  From:            Any / WAN
  Port:            41641
  Forward IP:      192.168.1.200
  Forward Port:    41641
  Protocol:        UDP
  Enable:          ✓
  Apply Changes
```

**pfSense / OPNsense:**
```
Firewall → NAT → Port Forward → Add
  Interface:             WAN
  Protocol:              UDP
  Destination:           WAN address
  Destination Port:      41641
  Redirect Target IP:    192.168.1.200
  Redirect Target Port:  41641
  Description:           vNode Tailscale
  Save → Apply Changes
```

#### Verification

Check connection type from Tailscale client:

```bash
tailscale status
# Look for "direct" not "relay" or "derp"
```

Mobile apps (iOS/Android):
- Ping the vNode from app
- Should show "Direct" not "Relayed"
- May take a few seconds to upgrade from Relayed to Direct

**Troubleshooting port forwarding:**
1. Verify protocol is UDP, not TCP
2. Check external port matches internal port
3. Verify router firewall allows the port
4. Some ISPs block ports - contact ISP if needed
5. Behind CG-NAT? Port forwarding won't work - contact ISP

### 3. Enable Exit Node in Tailscale Admin

1. Go to https://login.tailscale.com/admin/machines
2. Find your vNode hostname
3. Click "..." → "Edit route settings"
4. Toggle "Use as exit node"
5. Apply changes

## Advanced Networking

### VLAN Configuration

If using VLANs:

```bash
# For VLAN 10
docker network create -d macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  -o parent=eth0.10 \
  pub_net
```

Update `.env`:
```bash
MACVLAN_IP=192.168.10.200
GATEWAY_IP=192.168.10.1
MACVLAN_NETWORK=pub_net
```

### Multiple Subnets

If your network uses multiple subnets:

```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  --aux-address="exclude1=192.168.1.1" \
  --aux-address="exclude2=192.168.1.2" \
  -o parent=eth0 \
  pub_net
```

### Firewall Rules

Allow outbound connections:

```bash
# VPN connection
sudo ufw allow out 51820/udp

# Tailscale STUN
sudo ufw allow out 3478/udp

# Tailscale tunnel (for each instance)
sudo ufw allow out 41641/udp
sudo ufw allow out 41642/udp
sudo ufw allow out 41643/udp
```

### MTU and MSS Tuning

For performance issues, adjust in `.env`:

```bash
# Lower MTU for better compatibility
WIREGUARD_MTU=1280

# Adjust MSS clamping accordingly
# Formula: MTU - 40 (IP) - 20 (TCP)
TCP_MSS_CLAMP=1120
```

Common MTU values:
- 1280: Maximum compatibility, safest option
- 1360: Good balance
- 1420: Maximum performance, may have issues

### DNS Configuration

**Container DNS (for Tailscale control plane):**
```bash
DNS_SERVER=9.9.9.9   # Quad9 (privacy-focused)
# or
DNS_SERVER=1.1.1.1   # Cloudflare (fast)
# or
DNS_SERVER=8.8.8.8   # Google (reliable)
```

**Client DNS forwarding:**

By default, client DNS requests go through the VPN tunnel. To use specific DNS:

1. Configure DNS server on clients
2. Or set up DNS forwarding in vNode (advanced, requires modification)

### Bridge Networks

If you can't use MACVLAN (e.g., macOS Docker Desktop), use bridge mode:

**Note:** Bridge mode doesn't provide the same traffic separation. MACVLAN is strongly recommended on Linux hosts.

```yaml
networks:
  default:
    driver: bridge
```

Update `.env`:
```bash
# Remove MACVLAN settings
# Add port mappings in docker-compose.yml
```

This is **not recommended** for production use.

### Container Resource Limits

To limit resource usage, edit [docker-compose.yml](docker-compose.yml):

```yaml
services:
  gluetun:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Monitoring Multiple Instances

Create a monitoring script:

```bash
#!/bin/bash
# monitor-all.sh

while true; do
    clear
    echo "=== vNode Status ==="
    date
    echo ""

    for instance in us-east eu-west ap-south; do
        echo "--- $instance ---"
        vnode health $instance 2>/dev/null | grep -E "Status|VPN IP"
        echo ""
    done

    sleep 10
done
```

### Automated Updates

Set up cron jobs:

```cron
# Health checks every 5 minutes
*/5 * * * * vnode health us-east

# Update check daily
0 9 * * * vnode check-updates all

# Weekly update all instances
0 3 * * 0 vnode update all && vnode health all
```

### Backup Configuration

Backup your instance configurations:

```bash
#!/bin/bash
# backup-vnodes.sh

BACKUP_DIR=~/vnode-backups/$(date +%Y%m%d)
mkdir -p "$BACKUP_DIR"

# Backup all instance configs
for instance in ~/.local/share/vnode/instances/*/; do
    name=$(basename "$instance")
    cp "$instance/.env" "$BACKUP_DIR/${name}.env"
done

echo "Backed up to $BACKUP_DIR"
```

**Important:** `.env` files contain secrets. Store backups securely.

### High Availability

For critical deployments:

1. **Multiple instances** with different VPN providers
2. **Tailscale failover** - clients automatically switch if one exits fails
3. **Monitoring** with alerts
4. **Auto-restart** on failure (systemd service)

Example systemd service:

```ini
[Unit]
Description=vNode %I
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/user/.local/share/vnode/instances/%I
ExecStart=/usr/local/bin/vnode start %I
ExecStop=/usr/local/bin/vnode stop %I
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
```

Enable:
```bash
sudo systemctl enable vnode@us-east
sudo systemctl start vnode@us-east
```
