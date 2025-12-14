# Tailscale Virtual Exit Node (vNode)

A privacy-preserving Tailscale exit node that routes client traffic through a VPN while keeping Tailscale control plane traffic separate. This architecture ensures your Tailscale identity remains unlinkable to your VPN exit IP.

## What It Does

This creates a self-hosted exit node with intelligent traffic routing:

- **Tailscale Control Traffic** → Routes directly over your LAN (fast, reliable)
- **Client Internet Traffic** → Routes through VPN tunnel (private, encrypted)
- **Result**: Complete separation between your Tailscale identity and browsing activity

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         vNode Host                              │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  Tailscale Container                      │  │
│  │                                                           │  │
│  │   Tailscale Control Traffic ──→ Table 51 ──→ eth0 ──→ LAN │  │
│  │                                                           │  │
│  │   Client Data Traffic ──────────→ Table 52 ──→ tun0       │  │
│  │                                              (Gluetun)    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  eth0 (LAN Interface)              tun0 (VPN Tunnel)            │
│    ↓                                 ↓                          │
└────┼─────────────────────────────────┼──────────────────────────┘
     │                                 │
     ▼                                 ▼
  Local Network                   VPN Provider
  (Your Router)                   (WireGuard)
     │                                 │
     └────────────→ Internet ←─────────┘
```

### Traffic Separation

**Tailscale Control Plane** (marked packets → table 51):
- DERP relay connections
- Coordination protocol
- Routed directly via LAN interface (eth0)
- Never touches VPN tunnel

**Client Data Traffic** (default route → table 52):
- HTTP/HTTPS requests from clients
- All internet-bound traffic
- Routed through VPN tunnel (tun0)
- Exit IP is the VPN endpoint

This separation means:
- Tailscale sees: Your real IP, normal coordination traffic
- VPN provider sees: Encrypted client traffic, no Tailscale metadata
- **No correlation** between your Tailscale identity and VPN exit IP

## Key Features

- **One-line installation**: curl installer with automatic dependency setup
- **Interactive wizard**: Step-by-step configuration with smart defaults
- **Multi-instance support**: Run multiple vNodes with automatic conflict detection
- **Built-in monitoring**: Health checks, live dashboard, update checking
- **Provider agnostic**: Works with any WireGuard VPN (Mullvad, ProtonVPN, IVPN, etc.)
- **Direct P2P**: Works through NAT/CGNAT/cellular with optional port forwarding

## Quick Start

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/LadInTheLab/vnode/main/install.sh | bash
```

The installer:
- Detects your OS and architecture
- Checks for Docker (offers to install if missing)
- Sets up the vnode CLI in your PATH
- Creates config directories

### Create Instance

```bash
vnode create us-east
```

The interactive wizard:
- Guides you through all configuration
- Auto-detects conflicts with existing instances
- Suggests safe defaults for IPs, MACs, ports
- Validates configuration before deployment
- Shows post-deployment instructions

### Start and Use

```bash
# Start the instance
vnode start us-east

# Check health
vnode health us-east

# Monitor live
vnode monitor us-east
```

### Enable in Tailscale

1. Visit https://login.tailscale.com/admin/machines
2. Find your vNode hostname
3. Enable "Use as exit node"

### Use From Client

```bash
tailscale up --exit-node=us-east
curl ifconfig.me  # Should show VPN IP
```

## CLI Commands

```bash
# Instance management
vnode create [name]          Create new instance
vnode list                   List all instances
vnode start <name>|all       Start instance(s)
vnode stop <name>|all        Stop instance(s)
vnode status [name]          Show status
vnode delete <name>          Delete instance

# Monitoring
vnode health [name]          Run health check
vnode monitor <name>         Live dashboard
vnode ip <name>              Show VPN exit IP

# Maintenance
vnode update [name]          Update containers
vnode logs <name> [follow]   View logs
vnode shell <name> [container]  Shell access

# Configuration
vnode config <name> [edit]   View/edit config
vnode doctor                 System check
vnode help                   Show help
```

## Privacy Model

### What This Provides

**Network-Level Unlinkability**:
- Tailscale control plane traffic uses your LAN IP
- Traffic to/from clients uses your LAN IP
- Client data traffic exits via VPN IP
- These IPs are different and unlinked at the network level

**Direct P2P Connections**:
- Tailscale establishes direct UDP connections to vNode
- Works through NAT (tested up to triple NAT), CGNAT, cellular
- Port forwarding optional but recommended for best performance

**Traffic Encryption**:
- Client ↔ vNode: WireGuard (Tailscale)
- vNode ↔ Internet: WireGuard (VPN provider)

### Important Limitations

**VPNs Are Not Anonymity Tools**:
- You must trust your VPN provider with your traffic
- VPN provider can see destination IPs and traffic patterns
- For anonymity, use Tor or Nym (not a VPN)

**Trust Your vNode Host**:
- Traffic switches from Tailscale tunnel to VPN tunnel on the vNode
- The vNode can see unencrypted traffic during this switch
- Deploy vNodes only on hardware you physically control
- Containerization provides isolation but not absolute security

**Metadata Still Exists**:
- VPN provider sees: Traffic volume, timing, destinations
- Tailscale sees: Your control plane connections, peer relationships
- DNS queries reveal browsing patterns (use DoH/DoT if needed)

## Communication Map

A vNode communicates with exactly five types of endpoints:

```
┌─────────────┐
│   Clients   │ ← Your Tailscale devices using this as exit node
└──────┬──────┘
       │ WireGuard encrypted (Tailscale)
       ▼
┌─────────────┐
│    vNode    │
└──────┬──────┘
       │
       ├─→ VPN Servers         (WireGuard encrypted, your provider)
       ├─→ Tailscale DERP      (Fallback relay, if direct fails)
       ├─→ Tailscale Control   (Coordination, your real IP)
       └─→ Quad9 DNS (9.9.9.9) (Only for Tailscale discovery)
```

**No Third-Party Inspection**:
- vNode only touches packet headers, never inspects payloads
- Only your VPN provider sees destination IPs
- Tailscale control plane never sees client data traffic
- Direct DNS used only for Tailscale infrastructure resolution

## Use Cases

**Privacy-Conscious Browsing**:
- Separate your Tailscale identity from browsing activity
- VPN provider only sees encrypted traffic, not Tailscale metadata
- Useful when you trust your VPN provider more than your ISP

**Geographic Flexibility**:
- Deploy vNodes in different regions via different VPN endpoints
- Switch between locations from any Tailscale device
- Access region-specific content

**Network Bypass**:
- Useful on restrictive networks (hotels, public WiFi)
- Tailscale provides the tunnel, VPN provides the exit
- Direct P2P to your vNode, then VPN to internet

**Testing and Development**:
- Test applications from different geographic locations
- Verify CDN behavior across regions
- Simulate different network conditions

## Not Suitable For

**Anonymity**: If you need true anonymity, use Tor or ideally Nym. VPNs (including vNodes) require trusting a provider and do not provide anonymity guarantees.

**Untrusted Hardware**: Do not deploy vNodes on VPS providers or any hardware you don't control. The vNode has access to unencrypted traffic during tunnel switching.

**Compliance Circumvention**: Respect all applicable laws and terms of service. This tool does not provide legal protection for prohibited activities.

**High-Security Scenarios**: If your threat model includes nation-state actors or requires absolute guarantees, this solution is not appropriate. **No VPN provides protection against a global passive adversary.**

## About vNodes

vNodes are conceptually similar to the "Mullvad Exit Nodes" natively supported by Tailscale (currently a beta feature), but can be used with any VPN provider that supplies WireGuard configurations, and are controlled and administered by you rather than Tailscale (and aren't an add-on charge like Mullvad exit nodes).

Full disclosure - I like and support Mullvad. They have some of the strongest privacy policies available, and for a basic use case, the "just works" nature of the built-in Mullvad nodes is well worth the $5 per month upcharge on Tailscale. That said, using vNodes still has some advantages. The same $5 per month could be spent directly on a Mullvad subscription, in which case **you** would control your account (not Tailscale), **you** would manage payments (and can do so with cryptocurrencies including Bitcoin and Monero if you wish), and if you use less than 5 of the allowed Mullvad addresses for vNodes, you can still use the others for traditional VPN installations on other devices, which you can't do when purchasing from Tailscale. vNodes also give you freedom of choice. If you prefer (or already subscribe to) another VPN provider, so long as they can provide WireGuard configurations, they will work with vNodes. Though Mullvad is a leader in privacy, there are several commercial providers with acceptable privacy policies, and if you're informed and happy with your provider, I don't believe you should have to pay twice.

The main downside to vNodes as compared to native Mullvad exit nodes is latency. Because traffic has to make an "extra stop" at the vNode host before reaching the VPN server, your traffic takes a longer route than if your client device were connecting directly to the VPN. Whether or not this will create a problem depends on your use case - know that all VPNs introduce latency, the latency math for vNodes is just slightly different.

## System Requirements

- Docker 20.10+
- Docker Compose 1.27+ or Compose plugin
- Linux host with MACVLAN support
- WireGuard VPN subscription
- Tailscale account

## Documentation

- **README.md** (this file) - Overview and quick start
- **GUIDE.md** - Installation, configuration, usage
- **ADVANCED.md** - Multi-instance, networking, router setup

## Manual Installation (Power Users)

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

## Threat Model

**What this protects against**:
- Correlation of Tailscale identity with browsing traffic at the network level
- ISP inspection of browsing traffic (encrypted via VPN)
- Local network snooping on client traffic

**What this does NOT protect against**:
- VPN provider logging or analyzing traffic
- Browser fingerprinting and tracking
- Application-level metadata leaks
- Compromise of the vNode host itself
- Legal compulsion of VPN provider

## Security Considerations

**Container Isolation**: Docker provides process isolation but shares the kernel. A container escape would compromise the host.

**Privileged Containers**: Both containers run privileged for network stack access. This is required but reduces security boundaries.

**Secrets Management**: VPN keys and Tailscale auth keys stored in `.env` files (mode 600). Not encrypted at rest.

**Network Exposure**: vNode has MACVLAN interface on LAN. Firewall rules should restrict access to necessary ports only.

## Contributing

Contributions welcome. Please:
- Follow existing code style
- Test multi-instance scenarios
- Update documentation for changes

## License

Provided as-is for personal and educational use. Users are responsible for compliance with VPN provider terms and applicable laws.

## Acknowledgments

Built on [Gluetun](https://github.com/qdm12/gluetun) by @qdm12 for VPN management and [Tailscale](https://tailscale.com) for secure mesh networking.
