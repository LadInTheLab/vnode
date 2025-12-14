# Tailscale Virtual Exit Node (vNode)

A privacy-preserving Tailscale exit node that routes client traffic through a VPN while keeping Tailscale control plane traffic separate. This architecture ensures your Tailscale identity remains unlinkable to your VPN exit IP.

**Documentation**: [Installation Guide](GUIDE.md) • [Advanced Setup](ADVANCED.md) • [Security Model](SECURITY.md) • [Contributing](CONTRIBUTING.md)

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
│  eth0 (LAN Interface)                         tun0 (VPN Tunnel) │
│    ↓                                                   ↓        │
└────┼───────────────────────────────────────────────────┼────────┘
     │                                                   │
     ▼                                                   ▼
  Local Network                                    VPN Provider
  (Your Router)                                     (WireGuard)
     │                                                   │
     └───────────────────────→ Internet ←────────────────┘
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

## Privacy and Security

See [SECURITY.md](SECURITY.md) for complete details on:
- Privacy model and unlinkability guarantees
- Threat model and limitations
- What this protects against (and what it doesn't)
- Communication map and trust boundaries

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

## Important Limitations

**Not for anonymity**: Use Tor or Nym for anonymity. VPNs require trusting a provider.

**Not for untrusted hardware**: Deploy only on hardware you physically control.

**Not for high-security scenarios**: No VPN protects against global passive adversaries or nation-state actors.

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for manual installation instructions.

## License

Provided as-is for personal and educational use. Users are responsible for compliance with VPN provider terms and applicable laws.

## Acknowledgments

Built on [Gluetun](https://github.com/qdm12/gluetun) by @qdm12 for VPN management and [Tailscale](https://tailscale.com) for secure mesh networking.
