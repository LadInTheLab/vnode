# Security

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

## Threat Model

### What this protects against

- Correlation of Tailscale identity with browsing traffic at the network level
- ISP inspection of browsing traffic (encrypted via VPN)
- Local network snooping on client traffic

### What this does NOT protect against

- VPN provider logging or analyzing traffic
- Browser fingerprinting and tracking
- Application-level metadata leaks
- Compromise of the vNode host itself
- Legal compulsion of VPN provider
- Global passive adversaries

## Security Considerations

Note - these security considerations are not unique to vNodes - they are inherent to typical use of Docker and MACVLAN, but I feel compelled to point them out in the interest of transparency. 

**Container Isolation**: Docker provides process isolation but shares the kernel. A container escape would compromise the host.

**Privileged Containers**: Both containers run privileged for network stack access. This is required but reduces security boundaries.

**Secrets Management**: VPN keys and Tailscale auth keys stored in `.env` files (mode 600). Not encrypted at rest.

**Network Exposure**: vNode has MACVLAN interface on LAN. Firewall rules should restrict access to necessary ports only.

## Not Suitable For

**Anonymity**: If you need true anonymity, use Tor or ideally Nym. VPNs (including vNodes) require trusting a provider and do not provide anonymity guarantees.

**Untrusted Hardware**: Do not deploy vNodes on VPS providers or any hardware you don't control. The vNode has access to unencrypted traffic during tunnel switching.

**Compliance Circumvention**: Respect all applicable laws and terms of service. This tool does not provide legal protection for prohibited activities.

**High-Security Scenarios**: If your threat model includes nation-state actors or requires absolute guarantees, this solution is not appropriate. No VPN provides protection against a global passive adversary.

## Reporting Security Issues

If you discover a security vulnerability, please email the details to the repository maintainer. Do not open a public issue.
