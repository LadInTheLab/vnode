#!/bin/bash
#
# setup-wizard.sh - Interactive setup wizard for vNode
# Usage: ./setup-wizard.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration variables
declare -A CONFIG

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
prompt() { echo -e "${CYAN}[?]${NC} $1"; }
header() {
    echo ""
    echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${MAGENTA}  $1${NC}"
    echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Show welcome message
show_welcome() {
    clear
    cat << "EOF"
    ╔════════════════════════════════════════════════════════════╗
    ║                                                            ║
    ║         Tailscale Virtual Exit Node Setup Wizard          ║
    ║                                                            ║
    ║        This wizard will guide you through setting up      ║
    ║        your vNode with step-by-step configuration         ║
    ║                                                            ║
    ╚════════════════════════════════════════════════════════════╝

EOF
    echo -e "${GRAY}Press Enter to continue...${NC}"
    read -r
}

# Detect existing vNode instances
detect_existing_instances() {
    info "Scanning for existing vNode deployments..."

    local instances=()
    local used_ips=()
    local used_macs=()
    local used_ports=()

    # Find other vnode directories
    local parent_dir=$(dirname "$PROJECT_DIR")
    while IFS= read -r -d '' envfile; do
        local dir=$(dirname "$envfile")
        if [ "$dir" != "$PROJECT_DIR" ]; then
            instances+=("$dir")

            # Extract used values
            if [ -f "$envfile" ]; then
                local ip=$(grep "^MACVLAN_IP=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
                local mac=$(grep "^MACVLAN_MAC=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
                local port=$(grep "^TUNNEL_PORT=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)

                [ -n "$ip" ] && used_ips+=("$ip")
                [ -n "$mac" ] && used_macs+=("$mac")
                [ -n "$port" ] && used_ports+=("$port")
            fi
        fi
    done < <(find "$parent_dir" -maxdepth 2 -name ".env" -type f -print0 2>/dev/null)

    CONFIG[EXISTING_INSTANCES]="${#instances[@]}"
    CONFIG[USED_IPS]="${used_ips[*]}"
    CONFIG[USED_MACS]="${used_macs[*]}"
    CONFIG[USED_PORTS]="${used_ports[*]}"

    if [ "${#instances[@]}" -gt 0 ]; then
        echo ""
        warning "Found ${#instances[@]} existing vNode deployment(s):"
        for instance in "${instances[@]}"; do
            echo -e "  ${GRAY}→ $instance${NC}"
        done
        echo ""
        info "This wizard will help configure unique values for this instance"
        echo ""
    else
        success "No existing vNode deployments detected"
        echo ""
    fi
}

# Check if .env already exists
check_existing_env() {
    if [ -f "$PROJECT_DIR/.env" ]; then
        echo ""
        warning "Found existing .env file in this directory"
        echo ""
        prompt "Do you want to:"
        echo "  1) Overwrite with new configuration"
        echo "  2) Edit existing configuration"
        echo "  3) Exit and keep existing"
        echo ""
        read -p "Choice [1-3]: " -r choice

        case $choice in
            1)
                info "Creating backup of existing .env..."
                cp "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"
                success "Backup created"
                return 0
                ;;
            2)
                # Load existing values
                set -a
                source "$PROJECT_DIR/.env"
                set +a
                CONFIG[EDIT_MODE]=true
                return 0
                ;;
            3)
                echo "Exiting..."
                exit 0
                ;;
            *)
                error "Invalid choice"
                exit 1
                ;;
        esac
    fi
}

# Get network gateway
detect_gateway() {
    local gateway=""

    # Try Linux
    gateway=$(ip route | grep default | awk '{print $3}' 2>/dev/null | head -1 || true)

    # Try macOS
    if [ -z "$gateway" ]; then
        gateway=$(netstat -rn | grep default | grep -v ":" | awk '{print $2}' 2>/dev/null | head -1 || true)
    fi

    echo "$gateway"
}

# Get network interface
detect_interface() {
    local interface=""

    # Try Linux
    interface=$(ip route | grep default | awk '{print $5}' 2>/dev/null | head -1 || true)

    # Try macOS
    if [ -z "$interface" ]; then
        interface=$(netstat -rn | grep default | grep -v ":" | awk '{print $4}' 2>/dev/null | head -1 || true)
    fi

    echo "$interface"
}

# Generate random MAC address
generate_mac() {
    printf 'DE:AD:BE:EF:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256))
}

# Check if IP is in use
check_ip_in_use() {
    local ip=$1

    # Check against existing instances
    if [[ " ${CONFIG[USED_IPS]} " =~ " $ip " ]]; then
        return 0  # In use
    fi

    # Check with ping (quick check, 1 second timeout)
    if ping -c 1 -W 1 "$ip" &> /dev/null; then
        return 0  # In use
    fi

    return 1  # Available
}

# Suggest next available IP
suggest_next_ip() {
    local gateway=${CONFIG[GATEWAY_IP]}
    local subnet=$(echo "$gateway" | cut -d'.' -f1-3)
    local start=200  # Start at .200 to avoid typical DHCP ranges

    # If there are existing instances, increment from their IPs
    if [ -n "${CONFIG[USED_IPS]}" ]; then
        for used_ip in ${CONFIG[USED_IPS]}; do
            local octet=$(echo "$used_ip" | cut -d'.' -f4)
            if [ "$octet" -ge "$start" ]; then
                start=$((octet + 1))
            fi
        done
    fi

    # Find first available IP (200-254 range)
    for i in $(seq $start 254); do
        local test_ip="$subnet.$i"
        if ! check_ip_in_use "$test_ip"; then
            echo "$test_ip"
            return
        fi
    done

    # Fallback
    echo "$subnet.200"
}

# Suggest next available port
suggest_next_port() {
    local port=41641

    if [ -n "${CONFIG[USED_PORTS]}" ]; then
        for used_port in ${CONFIG[USED_PORTS]}; do
            if [ "$used_port" -ge "$port" ]; then
                port=$((used_port + 1))
            fi
        done
    fi

    echo "$port"
}

# Section: Tailscale Configuration
configure_tailscale() {
    header "Tailscale Configuration"

    info "You'll need a Tailscale auth key to authenticate this exit node."
    echo ""
    echo -e "${GRAY}To get an auth key:${NC}"
    echo -e "${GRAY}  1. Go to: ${CYAN}https://login.tailscale.com/admin/settings/keys${NC}"
    echo -e "${GRAY}  2. Generate a reusable auth key${NC}"
    echo -e "${GRAY}  3. Recommended: Add a tag like 'tag:exitnode'${NC}"
    echo ""

    # Auth key
    local default_auth="${TS_AUTHKEY:-}"
    if [ -n "$default_auth" ] && [ "$default_auth" != "tskey-auth-XXXXXXXXXXXXXXXXXXXXX" ]; then
        prompt "Tailscale auth key [keep existing]:"
        read -r auth_key
        auth_key=${auth_key:-$default_auth}
    else
        prompt "Tailscale auth key:"
        read -r auth_key
        while [ -z "$auth_key" ] || [[ "$auth_key" == *"XXXX"* ]]; do
            error "Please enter a valid auth key"
            read -r auth_key
        done
    fi
    CONFIG[TS_AUTHKEY]="$auth_key"

    # Hostname
    local instance_num=$((${CONFIG[EXISTING_INSTANCES]} + 1))
    local default_hostname="${TS_HOSTNAME:-vnode-$instance_num}"

    echo ""
    prompt "Hostname for this exit node [${GREEN}$default_hostname${NC}]:"
    read -r hostname
    hostname=${hostname:-$default_hostname}
    CONFIG[TS_HOSTNAME]="$hostname"

    success "Tailscale configured: $hostname"
}

# Section: Network Configuration
configure_network() {
    header "Network Configuration"

    # Detect gateway
    local detected_gateway=$(detect_gateway)
    local default_gateway="${GATEWAY_IP:-$detected_gateway}"

    if [ -n "$detected_gateway" ]; then
        info "Detected gateway: $detected_gateway"
        prompt "Your router/gateway IP [${GREEN}$default_gateway${NC}]:"
    else
        warning "Could not auto-detect gateway"
        prompt "Your router/gateway IP (usually 192.168.1.1):"
    fi
    read -r gateway
    gateway=${gateway:-$default_gateway}

    # Validate IP format
    while ! [[ "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        error "Invalid IP format"
        read -r gateway
    done
    CONFIG[GATEWAY_IP]="$gateway"

    # MACVLAN IP
    echo ""
    local suggested_ip=$(suggest_next_ip)
    local default_ip="${MACVLAN_IP:-$suggested_ip}"

    if [ "${CONFIG[EXISTING_INSTANCES]}" -gt 0 ]; then
        info "Existing instance IPs: ${CONFIG[USED_IPS]}"
        info "Suggested IP (next available): $suggested_ip"
    else
        info "Recommended: Use IPs in the .200-254 range"
        warning "Configure your router DHCP to only assign IPs up to .199"
        info "Example: If using 192.168.1.200, set DHCP range to 192.168.1.100-192.168.1.199"
    fi

    prompt "MACVLAN IP for this vNode [${GREEN}$default_ip${NC}]:"
    read -r macvlan_ip
    macvlan_ip=${macvlan_ip:-$default_ip}

    # Validate IP and check for conflicts
    while ! [[ "$macvlan_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        error "Invalid IP format"
        read -r macvlan_ip
    done

    if check_ip_in_use "$macvlan_ip"; then
        warning "IP $macvlan_ip appears to be in use or assigned to another instance"
        prompt "Use it anyway? (y/N):"
        read -r use_anyway
        if [[ ! "$use_anyway" =~ ^[Yy]$ ]]; then
            prompt "Enter a different IP:"
            read -r macvlan_ip
        fi
    fi
    CONFIG[MACVLAN_IP]="$macvlan_ip"

    # MAC Address
    echo ""
    local suggested_mac=$(generate_mac)
    local default_mac="${MACVLAN_MAC:-$suggested_mac}"

    # Ensure MAC is unique
    while [[ " ${CONFIG[USED_MACS]} " =~ " $default_mac " ]]; do
        default_mac=$(generate_mac)
    done

    info "Generated unique MAC address: $default_mac"
    prompt "MACVLAN MAC address [${GREEN}$default_mac${NC}]:"
    read -r macvlan_mac
    macvlan_mac=${macvlan_mac:-$default_mac}

    # Validate MAC format
    while ! [[ "$macvlan_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; do
        error "Invalid MAC format (should be XX:XX:XX:XX:XX:XX)"
        read -r macvlan_mac
    done
    CONFIG[MACVLAN_MAC]="$macvlan_mac"

    # Tailscale port
    echo ""
    local suggested_port=$(suggest_next_port)
    local default_port="${TUNNEL_PORT:-$suggested_port}"

    if [ "${CONFIG[EXISTING_INSTANCES]}" -gt 0 ]; then
        info "Each vNode instance needs a unique port"
        info "Existing instance ports: ${CONFIG[USED_PORTS]}"
        info "Suggested port (next available): $suggested_port"
    fi

    prompt "Tailscale tunnel port [${GREEN}$default_port${NC}]:"
    read -r tunnel_port
    tunnel_port=${tunnel_port:-$default_port}
    CONFIG[TUNNEL_PORT]="$tunnel_port"

    # MACVLAN network name
    echo ""
    local default_network="${MACVLAN_NETWORK:-pub_net}"
    prompt "MACVLAN network name [${GREEN}$default_network${NC}]:"
    read -r network_name
    network_name=${network_name:-$default_network}
    CONFIG[MACVLAN_NETWORK]="$network_name"

    success "Network configured"
}

# Section: VPN Configuration
configure_vpn() {
    header "VPN Configuration (WireGuard)"

    info "You'll need a WireGuard configuration from your VPN provider"
    echo ""
    echo -e "${GRAY}Popular providers:${NC}"
    echo -e "${GRAY}  • Mullvad:    ${CYAN}https://mullvad.net/account/#/wireguard-config${NC}"
    echo -e "${GRAY}  • ProtonVPN:  ${CYAN}https://account.protonvpn.com/downloads${NC}"
    echo -e "${GRAY}  • IVPN:       ${CYAN}https://www.ivpn.net/account${NC}"
    echo ""

    prompt "Do you have your WireGuard config file? (Y/n):"
    read -r has_config

    if [[ "$has_config" =~ ^[Nn]$ ]]; then
        echo ""
        warning "Please obtain a WireGuard configuration from your VPN provider first"
        echo "Then run this wizard again, or manually edit .env"
        exit 1
    fi

    # Private key
    echo ""
    local default_private="${VPN_PRIVATE_KEY:-}"
    if [ -n "$default_private" ] && [[ ! "$default_private" == *"your_"* ]]; then
        prompt "WireGuard private key [keep existing]:"
        read -r private_key
        private_key=${private_key:-$default_private}
    else
        prompt "WireGuard private key (from [Interface] section):"
        read -r private_key
        while [ -z "$private_key" ] || [[ "$private_key" == *"your_"* ]]; do
            error "Please enter a valid private key"
            read -r private_key
        done
    fi
    CONFIG[VPN_PRIVATE_KEY]="$private_key"

    # Public key
    echo ""
    local default_public="${VPN_PUBLIC_KEY:-}"
    if [ -n "$default_public" ] && [[ ! "$default_public" == *"your_"* ]]; then
        prompt "Server public key [keep existing]:"
        read -r public_key
        public_key=${public_key:-$default_public}
    else
        prompt "Server public key (from [Peer] section):"
        read -r public_key
        while [ -z "$public_key" ]; do
            error "Please enter the server's public key"
            read -r public_key
        done
    fi
    CONFIG[VPN_PUBLIC_KEY]="$public_key"

    # Endpoint IP
    echo ""
    local default_endpoint="${VPN_ENDPOINT_IP:-}"
    if [ -n "$default_endpoint" ] && [[ ! "$default_endpoint" == *"vpn.server"* ]]; then
        prompt "VPN server IP [keep existing]:"
        read -r endpoint_ip
        endpoint_ip=${endpoint_ip:-$default_endpoint}
    else
        prompt "VPN server IP (from Endpoint, before the colon):"
        read -r endpoint_ip
        while ! [[ "$endpoint_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
            error "Invalid IP format"
            read -r endpoint_ip
        done
    fi
    CONFIG[VPN_ENDPOINT_IP]="$endpoint_ip"

    # Port
    echo ""
    local default_port="${VPN_PORT:-51820}"
    prompt "VPN server port [${GREEN}$default_port${NC}]:"
    read -r vpn_port
    vpn_port=${vpn_port:-$default_port}
    CONFIG[VPN_PORT]="$vpn_port"

    # Tunnel IP
    echo ""
    local default_tunnel_ip="${VPN_IP:-}"
    if [ -n "$default_tunnel_ip" ] && [[ ! "$default_tunnel_ip" == *"10.x"* ]]; then
        prompt "Your VPN tunnel IP with /32 [keep existing]:"
        read -r tunnel_ip
        tunnel_ip=${tunnel_ip:-$default_tunnel_ip}
    else
        prompt "Your VPN tunnel IP (from [Interface] Address, e.g., 10.x.x.x/32):"
        read -r tunnel_ip
        while [ -z "$tunnel_ip" ]; do
            error "Please enter your tunnel IP"
            read -r tunnel_ip
        done
    fi
    CONFIG[VPN_IP]="$tunnel_ip"

    success "VPN configured"
}

# Section: Optional settings
configure_optional() {
    header "Optional Settings"

    prompt "Configure advanced options? (y/N):"
    read -r configure_advanced

    if [[ "$configure_advanced" =~ ^[Yy]$ ]]; then
        # DNS
        echo ""
        local default_dns="${DNS_SERVER:-9.9.9.9}"
        info "DNS options: 9.9.9.9 (Quad9), 1.1.1.1 (Cloudflare), 8.8.8.8 (Google)"
        prompt "DNS server [${GREEN}$default_dns${NC}]:"
        read -r dns
        CONFIG[DNS_SERVER]=${dns:-$default_dns}

        # MTU
        echo ""
        local default_mtu="${WIREGUARD_MTU:-1280}"
        info "MTU range: 1280 (safest) to 1420. Use 1280 if unsure. Oversizing MTU or the MSS clamp can drastically reduce speed."
        prompt "WireGuard MTU [${GREEN}$default_mtu${NC}]:"
        read -r mtu
        CONFIG[WIREGUARD_MTU]=${mtu:-$default_mtu}

        # Keepalive
        echo ""
        local default_keepalive="${WIREGUARD_KEEPALIVE:-25}"
        prompt "WireGuard keepalive interval in seconds [${GREEN}$default_keepalive${NC}]:"
        read -r keepalive
        CONFIG[WIREGUARD_KEEPALIVE]=${keepalive:-$default_keepalive}

        # MSS Clamp
        echo ""
        local default_mss="${TCP_MSS_CLAMP:-1120}"
        prompt "TCP MSS clamp value [${GREEN}$default_mss${NC}]:"
        read -r mss
        CONFIG[TCP_MSS_CLAMP]=${mss:-$default_mss}
    else
        # Set defaults
        CONFIG[DNS_SERVER]="${DNS_SERVER:-9.9.9.9}"
        CONFIG[WIREGUARD_MTU]="${WIREGUARD_MTU:-1280}"
        CONFIG[WIREGUARD_KEEPALIVE]="${WIREGUARD_KEEPALIVE:-25}"
        CONFIG[TCP_MSS_CLAMP]="${TCP_MSS_CLAMP:-1120}"
    fi

    CONFIG[HEALTHCHECK_INTERVAL]="${HEALTHCHECK_INTERVAL:-300}"
    CONFIG[CHECK_UPDATES]="${CHECK_UPDATES:-true}"

    success "Optional settings configured"
}

# Show configuration summary
show_summary() {
    header "Configuration Summary"

    echo -e "${BOLD}Tailscale:${NC}"
    echo -e "  Hostname:        ${GREEN}${CONFIG[TS_HOSTNAME]}${NC}"
    echo -e "  Auth Key:        ${GRAY}${CONFIG[TS_AUTHKEY]:0:20}...${NC}"
    echo ""

    echo -e "${BOLD}Network:${NC}"
    echo -e "  Gateway:         ${GREEN}${CONFIG[GATEWAY_IP]}${NC}"
    echo -e "  MACVLAN IP:      ${GREEN}${CONFIG[MACVLAN_IP]}${NC}"
    echo -e "  MACVLAN MAC:     ${GREEN}${CONFIG[MACVLAN_MAC]}${NC}"
    echo -e "  Tunnel Port:     ${GREEN}${CONFIG[TUNNEL_PORT]}${NC}"
    echo -e "  Network Name:    ${GREEN}${CONFIG[MACVLAN_NETWORK]}${NC}"
    echo ""

    echo -e "${BOLD}VPN:${NC}"
    echo -e "  Endpoint:        ${GREEN}${CONFIG[VPN_ENDPOINT_IP]}:${CONFIG[VPN_PORT]}${NC}"
    echo -e "  Tunnel IP:       ${GREEN}${CONFIG[VPN_IP]}${NC}"
    echo -e "  Private Key:     ${GRAY}${CONFIG[VPN_PRIVATE_KEY]:0:20}...${NC}"
    echo ""

    echo -e "${BOLD}Advanced:${NC}"
    echo -e "  DNS:             ${GREEN}${CONFIG[DNS_SERVER]}${NC}"
    echo -e "  MTU:             ${GREEN}${CONFIG[WIREGUARD_MTU]}${NC}"
    echo -e "  Keepalive:       ${GREEN}${CONFIG[WIREGUARD_KEEPALIVE]}s${NC}"
    echo -e "  TCP MSS:         ${GREEN}${CONFIG[TCP_MSS_CLAMP]}${NC}"
    echo ""
}

# Write .env file
write_env_file() {
    info "Writing configuration to .env file..."

    cat > "$PROJECT_DIR/.env" << EOF
# Generated by setup wizard on $(date)
# vNode instance $(($RANDOM % 10000))

# ============================================================================
# TAILSCALE CONFIGURATION
# ============================================================================
TS_AUTHKEY=${CONFIG[TS_AUTHKEY]}
TS_HOSTNAME=${CONFIG[TS_HOSTNAME]}

# ============================================================================
# NETWORK CONFIGURATION
# ============================================================================
MACVLAN_IP=${CONFIG[MACVLAN_IP]}
MACVLAN_MAC=${CONFIG[MACVLAN_MAC]}
GATEWAY_IP=${CONFIG[GATEWAY_IP]}
MACVLAN_NETWORK=${CONFIG[MACVLAN_NETWORK]}
TUNNEL_PORT=${CONFIG[TUNNEL_PORT]}

# ============================================================================
# VPN CONFIGURATION (WIREGUARD)
# ============================================================================
VPN_PRIVATE_KEY=${CONFIG[VPN_PRIVATE_KEY]}
VPN_PUBLIC_KEY=${CONFIG[VPN_PUBLIC_KEY]}
VPN_ENDPOINT_IP=${CONFIG[VPN_ENDPOINT_IP]}
VPN_PORT=${CONFIG[VPN_PORT]}
VPN_IP=${CONFIG[VPN_IP]}

# ============================================================================
# ADVANCED SETTINGS
# ============================================================================
DNS_SERVER=${CONFIG[DNS_SERVER]}
WIREGUARD_MTU=${CONFIG[WIREGUARD_MTU]}
WIREGUARD_KEEPALIVE=${CONFIG[WIREGUARD_KEEPALIVE]}
TCP_MSS_CLAMP=${CONFIG[TCP_MSS_CLAMP]}

# ============================================================================
# MONITORING
# ============================================================================
HEALTHCHECK_INTERVAL=${CONFIG[HEALTHCHECK_INTERVAL]}
CHECK_UPDATES=${CONFIG[CHECK_UPDATES]}
EOF

    chmod 600 "$PROJECT_DIR/.env"
    success "Configuration saved to .env"
}

# Show post-deployment instructions
show_post_deployment() {
    header "Important Router Configuration"

    echo -e "${YELLOW}${BOLD}Before using your vNode, configure your router:${NC}\n"

    # DHCP Configuration
    echo -e "${CYAN}1. Configure DHCP Range${NC}"
    echo -e "   Your vNode uses IP: ${GREEN}${CONFIG[MACVLAN_IP]}${NC}"
    echo ""
    echo -e "   ${BOLD}Action Required:${NC}"
    echo -e "   • Log into your router (usually http://${CONFIG[GATEWAY_IP]})"
    echo -e "   • Go to DHCP settings"
    echo -e "   • Set DHCP range to end BEFORE your vNode IPs"

    local vnode_octet=$(echo "${CONFIG[MACVLAN_IP]}" | cut -d'.' -f4)
    local suggested_dhcp_end=$((vnode_octet - 1))
    local subnet=$(echo "${CONFIG[MACVLAN_IP]}" | cut -d'.' -f1-3)

    echo -e "   • Recommended DHCP range: ${GREEN}${subnet}.100 - ${subnet}.${suggested_dhcp_end}${NC}"
    echo -e "   • This prevents conflicts with your vNode at ${subnet}.${vnode_octet}+"
    echo ""

    # Port Forwarding
    echo -e "${CYAN}2. Configure Port Forwarding (For External Access)${NC}"
    echo -e "   Tailscale port: ${GREEN}${CONFIG[TUNNEL_PORT]}${NC}"
    echo ""
    echo -e "   ${BOLD}Action Required:${NC}"
    echo -e "   • Log into your router"
    echo -e "   • Go to Port Forwarding / NAT settings"
    echo -e "   • Create a new rule:"
    echo ""
    echo -e "     ${BOLD}Protocol:${NC}       UDP"
    echo -e "     ${BOLD}External Port:${NC}  ${GREEN}${CONFIG[TUNNEL_PORT]}${NC}"
    echo -e "     ${BOLD}Internal IP:${NC}    ${GREEN}${CONFIG[MACVLAN_IP]}${NC}"
    echo -e "     ${BOLD}Internal Port:${NC}  ${GREEN}${CONFIG[TUNNEL_PORT]}${NC}"
    echo -e "     ${BOLD}Description:${NC}    vNode ${CONFIG[TS_HOSTNAME]}"
    echo ""
    echo -e "   ${GRAY}Note: This allows Tailscale to accept direct connections${NC}"
    echo -e "   ${GRAY}Without it, vNode still works but uses DERP relay${NC}"
    echo ""

    # Additional port forwarding for multiple instances
    if [ "${CONFIG[EXISTING_INSTANCES]}" -gt 0 ]; then
        echo -e "   ${YELLOW}WARNING: You have ${CONFIG[EXISTING_INSTANCES]} other instance(s)${NC}"
        echo -e "   ${YELLOW}Each needs its own port forwarding rule!${NC}"
        echo ""
    fi

    # Tailscale Admin
    echo -e "${CYAN}3. Enable Exit Node in Tailscale${NC}"
    echo ""
    echo -e "   After deployment completes:"
    echo -e "   • Go to: ${GREEN}https://login.tailscale.com/admin/machines${NC}"
    echo -e "   • Find: ${GREEN}${CONFIG[TS_HOSTNAME]}${NC}"
    echo -e "   • Click the '...' menu → 'Edit route settings'"
    echo -e "   • Toggle ${GREEN}'Use as exit node'${NC} to ON"
    echo ""

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    read -p "Press Enter when you've noted these settings..."
    echo ""
}

# Offer to deploy
offer_deployment() {
    header "Next Steps"

    echo -e "${GREEN}✓ Configuration complete!${NC}"
    echo ""
    echo "Your .env file has been created with all settings."
    echo ""

    # Check if MACVLAN network exists
    local network_name="${CONFIG[MACVLAN_NETWORK]}"
    if ! docker network inspect "$network_name" &> /dev/null; then
        warning "MACVLAN network '$network_name' does not exist yet"
        echo ""
        echo "You need to create it first:"
        echo ""
        local subnet=$(echo "${CONFIG[GATEWAY_IP]}" | cut -d'.' -f1-3).0/24
        local interface=$(detect_interface)
        echo -e "${CYAN}docker network create -d macvlan \\${NC}"
        echo -e "${CYAN}  --subnet=$subnet \\${NC}"
        echo -e "${CYAN}  --gateway=${CONFIG[GATEWAY_IP]} \\${NC}"
        echo -e "${CYAN}  -o parent=${interface:-eth0} \\${NC}"
        echo -e "${CYAN}  $network_name${NC}"
        echo ""
        prompt "Create this network now? (Y/n):"
        read -r create_network

        if [[ ! "$create_network" =~ ^[Nn]$ ]]; then
            info "Creating MACVLAN network..."
            if docker network create -d macvlan \
                --subnet="$subnet" \
                --gateway="${CONFIG[GATEWAY_IP]}" \
                -o parent="${interface:-eth0}" \
                "$network_name" &> /dev/null; then
                success "Network created successfully"
                echo ""
            else
                error "Failed to create network - you may need to adjust the parent interface"
                echo "Run the command manually with your correct network interface"
                echo ""
            fi
        fi
    fi

    # Show post-deployment instructions BEFORE deploying
    show_post_deployment

    prompt "Would you like to deploy the vNode now? (Y/n):"
    read -r deploy_now

    if [[ ! "$deploy_now" =~ ^[Nn]$ ]]; then
        echo ""
        info "Running deployment..."
        echo ""
        "$SCRIPT_DIR/deploy.sh"

        # Show reminders after deployment
        echo ""
        show_deployment_reminders
    else
        echo ""
        info "To deploy later, run:"
        echo -e "  ${CYAN}./scripts/deploy.sh${NC}"
        echo ""
        info "To validate configuration:"
        echo -e "  ${CYAN}./scripts/deploy.sh --validate-only${NC}"
        echo ""
    fi
}

# Show reminders after deployment
show_deployment_reminders() {
    echo ""
    echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}${BOLD}  IMPORTANT REMINDERS${NC}"
    echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}1. Router DHCP:${NC} Configure DHCP to avoid ${CONFIG[MACVLAN_IP]}"
    echo -e "${BOLD}2. Port Forward:${NC} Forward UDP ${CONFIG[TUNNEL_PORT]} → ${CONFIG[MACVLAN_IP]}:${CONFIG[TUNNEL_PORT]}"
    echo -e "${BOLD}3. Tailscale Admin:${NC} Enable '${CONFIG[TS_HOSTNAME]}' as exit node"
    echo ""
    echo -e "Full details: ${CYAN}$PROJECT_DIR/POST-DEPLOYMENT.md${NC}"
    echo ""
}

# Main wizard flow
main() {
    show_welcome
    detect_existing_instances
    check_existing_env

    configure_tailscale
    configure_network
    configure_vpn
    configure_optional

    show_summary

    echo ""
    prompt "Save this configuration? (Y/n):"
    read -r save_config

    if [[ "$save_config" =~ ^[Nn]$ ]]; then
        warning "Configuration not saved. Exiting."
        exit 0
    fi

    write_env_file
    offer_deployment

    echo ""
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  Setup complete! Your vNode is ready.${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Quick commands:"
    echo -e "  ${CYAN}./scripts/manage.sh status${NC}   - Check status"
    echo -e "  ${CYAN}./scripts/manage.sh monitor${NC}  - Live dashboard"
    echo -e "  ${CYAN}./scripts/manage.sh health${NC}   - Health check"
    echo ""
}

main "$@"
