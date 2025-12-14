#!/bin/bash
#
# deploy.sh - Deploy Tailscale Virtual Exit Node
# Usage: ./deploy.sh [--validate-only] [--skip-network-check]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VALIDATE_ONLY=false
SKIP_NETWORK_CHECK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --validate-only) VALIDATE_ONLY=true; shift ;;
        --skip-network-check) SKIP_NETWORK_CHECK=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
fatal() { error "$1"; exit 1; }

# Check if .env exists
check_env_file() {
    info "Checking for .env file..."
    if [ ! -f "$PROJECT_DIR/.env" ]; then
        fatal ".env file not found. Copy .env.template to .env and configure it."
    fi
    success ".env file found"
}

# Validate environment variables
validate_env() {
    info "Validating environment variables..."

    # Load .env
    set -a
    source "$PROJECT_DIR/.env"
    set +a

    local required_vars=(
        "TS_AUTHKEY"
        "MACVLAN_IP"
        "MACVLAN_MAC"
        "GATEWAY_IP"
        "VPN_PRIVATE_KEY"
        "VPN_PUBLIC_KEY"
        "VPN_ENDPOINT_IP"
        "VPN_PORT"
        "VPN_IP"
    )

    local missing=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            echo "  • $var"
        done
        exit 1
    fi

    # Check for placeholder values
    if [[ "$TS_AUTHKEY" == *"XXXX"* ]]; then
        fatal "TS_AUTHKEY appears to be a placeholder. Update .env with real values."
    fi

    if [[ "$VPN_PRIVATE_KEY" == *"your_"* ]]; then
        fatal "VPN credentials appear to be placeholders. Update .env with real values."
    fi

    # Validate IP formats
    if ! [[ "$MACVLAN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fatal "MACVLAN_IP is not a valid IP address"
    fi

    if ! [[ "$GATEWAY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fatal "GATEWAY_IP is not a valid IP address"
    fi

    if ! [[ "$VPN_ENDPOINT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fatal "VPN_ENDPOINT_IP is not a valid IP address"
    fi

    # Validate MAC address format
    if ! [[ "$MACVLAN_MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        fatal "MACVLAN_MAC is not a valid MAC address"
    fi

    success "Environment variables validated"
}

# Check for conflicts with other vNode instances
check_multi_instance_conflicts() {
    info "Checking for conflicts with other vNode deployments..."

    local current_dir="$PROJECT_DIR"
    local parent_dir=$(dirname "$current_dir")
    local conflicts=()

    # Load current instance values
    set -a
    source "$PROJECT_DIR/.env"
    set +a

    local current_ip="$MACVLAN_IP"
    local current_mac="$MACVLAN_MAC"
    local current_port="$TUNNEL_PORT"

    # Scan for other .env files
    while IFS= read -r -d '' envfile; do
        local other_dir=$(dirname "$envfile")

        # Skip if it's the current directory
        if [ "$other_dir" = "$current_dir" ]; then
            continue
        fi

        # Load other instance values
        local other_ip=$(grep "^MACVLAN_IP=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
        local other_mac=$(grep "^MACVLAN_MAC=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
        local other_port=$(grep "^TUNNEL_PORT=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
        local other_hostname=$(grep "^TS_HOSTNAME=" "$envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)

        # Check for conflicts
        if [ "$current_ip" = "$other_ip" ] && [ -n "$other_ip" ]; then
            conflicts+=("IP $current_ip is used by another instance at $other_dir")
        fi

        if [ "$current_mac" = "$other_mac" ] && [ -n "$other_mac" ]; then
            conflicts+=("MAC $current_mac is used by another instance at $other_dir")
        fi

        if [ "$current_port" = "$other_port" ] && [ -n "$other_port" ]; then
            conflicts+=("Port $current_port is used by another instance at $other_dir (hostname: $other_hostname)")
        fi
    done < <(find "$parent_dir" -maxdepth 2 -name ".env" -type f -print0 2>/dev/null)

    if [ ${#conflicts[@]} -gt 0 ]; then
        error "Detected conflicts with other vNode instances:"
        for conflict in "${conflicts[@]}"; do
            echo "  • $conflict"
        done
        echo ""
        warning "Each vNode instance must have unique:"
        echo "  - MACVLAN_IP"
        echo "  - MACVLAN_MAC"
        echo "  - TUNNEL_PORT"
        echo ""
        echo "Run ./scripts/setup-wizard.sh to reconfigure with automatic conflict detection"
        echo ""
        fatal "Deployment aborted due to conflicts"
    fi

    success "No conflicts detected with other instances"
}

# Check Docker
check_docker() {
    info "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        fatal "Docker is not installed"
    fi

    if ! docker info &> /dev/null; then
        fatal "Docker daemon is not running"
    fi

    success "Docker is running"
}

# Check Docker Compose
check_docker_compose() {
    info "Checking Docker Compose..."

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        fatal "Docker Compose is not installed"
    fi

    success "Docker Compose is available"
}

# Check MACVLAN network
check_macvlan_network() {
    if [ "$SKIP_NETWORK_CHECK" = true ]; then
        warning "Skipping MACVLAN network check"
        return
    fi

    info "Checking MACVLAN network..."

    # Load .env to get network name
    set -a
    source "$PROJECT_DIR/.env"
    set +a

    local network_name="${MACVLAN_NETWORK:-pub_net}"

    if ! docker network inspect "$network_name" &> /dev/null; then
        warning "MACVLAN network '$network_name' not found"
        echo ""
        echo "You need to create a MACVLAN network. Example:"
        echo ""
        echo "  docker network create -d macvlan \\"
        echo "    --subnet=192.168.1.0/24 \\"
        echo "    --gateway=192.168.1.1 \\"
        echo "    -o parent=eth0 \\"
        echo "    $network_name"
        echo ""
        echo "Adjust subnet, gateway, and parent interface for your network."
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        success "MACVLAN network '$network_name' exists"
    fi
}

# Check for IP conflicts
check_ip_conflicts() {
    if [ "$SKIP_NETWORK_CHECK" = true ]; then
        return
    fi

    info "Checking for IP conflicts..."

    set -a
    source "$PROJECT_DIR/.env"
    set +a

    # Ping the IP to see if it's in use
    if ping -c 1 -W 1 "$MACVLAN_IP" &> /dev/null; then
        warning "IP $MACVLAN_IP is responding to ping (may be in use)"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        success "IP $MACVLAN_IP appears to be available"
    fi
}

# Check file permissions
check_permissions() {
    info "Checking .env file permissions..."

    local perms=$(stat -f "%Lp" "$PROJECT_DIR/.env" 2>/dev/null || stat -c "%a" "$PROJECT_DIR/.env" 2>/dev/null)

    if [ "$perms" != "600" ]; then
        warning ".env file permissions are $perms (should be 600)"
        chmod 600 "$PROJECT_DIR/.env"
        success "Fixed .env permissions to 600"
    else
        success ".env permissions are secure (600)"
    fi
}

# Create required directories
create_directories() {
    info "Creating required directories..."

    mkdir -p "$PROJECT_DIR/tailscale-state"
    mkdir -p "$PROJECT_DIR/logs/gluetun"
    mkdir -p "$PROJECT_DIR/logs/tailscale"

    success "Directories created"
}

# Pull Docker images
pull_images() {
    info "Pulling Docker images..."

    cd "$PROJECT_DIR"
    if docker-compose pull 2>/dev/null || docker compose pull 2>/dev/null; then
        success "Docker images pulled"
    else
        fatal "Failed to pull Docker images"
    fi
}

# Deploy containers
deploy_containers() {
    info "Deploying containers..."

    cd "$PROJECT_DIR"
    if docker-compose up -d 2>/dev/null || docker compose up -d 2>/dev/null; then
        success "Containers deployed"
    else
        fatal "Failed to deploy containers"
    fi
}

# Wait for containers to be healthy
wait_for_health() {
    info "Waiting for containers to become healthy..."

    local max_wait=120
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local gluetun_health=$(docker inspect -f '{{.State.Health.Status}}' gluetun-vnode 2>/dev/null || echo "starting")

        if [ "$gluetun_health" = "healthy" ]; then
            success "Containers are healthy"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done

    echo ""
    warning "Containers did not become healthy within ${max_wait}s"
    return 1
}

# Main deployment flow
main() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Tailscale Virtual Exit Node Deployment${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    check_env_file
    validate_env
    check_multi_instance_conflicts
    check_docker
    check_docker_compose
    check_macvlan_network
    check_ip_conflicts
    check_permissions
    create_directories

    if [ "$VALIDATE_ONLY" = true ]; then
        echo ""
        success "Validation complete! Ready to deploy."
        echo ""
        echo "To deploy, run: $0"
        exit 0
    fi

    echo ""
    info "Starting deployment..."
    echo ""

    pull_images
    deploy_containers
    wait_for_health || true

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Deployment Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo "Next steps:"
    echo "  1. Check container logs: docker-compose logs -f"
    echo "  2. Run health check: ./scripts/health-check.sh"
    echo "  3. View monitoring dashboard: ./scripts/monitor.sh"
    echo ""
    echo "Enable the exit node in Tailscale:"
    echo "  https://login.tailscale.com/admin/machines"
    echo ""
}

main "$@"
