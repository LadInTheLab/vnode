#!/bin/bash
#
# vNode Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/LadInTheLab/vnode/main/install.sh | bash
# Or: wget -qO- https://raw.githubusercontent.com/LadInTheLab/vnode/main/install.sh | bash
#

set -euo pipefail

# Constants
VNODE_VERSION="1.0.0"
GITHUB_REPO="${VNODE_REPO:-LadInTheLab/vnode}"

# Paths set by check_root() based on privilege level
INSTALL_DIR=""
BIN_DIR=""
CONFIG_DIR=""
INSTANCES_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
fatal() { error "$1"; exit 1; }

# Show banner
show_banner() {
    cat << "EOF"
    ╔════════════════════════════════════════════════════════════╗
    ║                                                            ║
    ║              Tailscale Virtual Exit Node                   ║
    ║                    vNode Installer                         ║
    ║                                                            ║
    ╚════════════════════════════════════════════════════════════╝

EOF
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        warning "Running as root. Installation will be system-wide."
        INSTALL_DIR="/opt/vnode"
        BIN_DIR="/usr/local/bin"
        CONFIG_DIR="/etc/vnode"
        INSTANCES_DIR="/var/lib/vnode/instances"
    else
        info "Running as user. Installation will be user-local."
        INSTALL_DIR="${VNODE_INSTALL_DIR:-$HOME/.local/share/vnode}"
        BIN_DIR="${VNODE_BIN_DIR:-$HOME/.local/bin}"
        CONFIG_DIR="${VNODE_CONFIG_DIR:-$HOME/.config/vnode}"
        INSTANCES_DIR="${VNODE_INSTANCES_DIR:-$HOME/.local/share/vnode/instances}"
    fi
}

# Detect OS and architecture
detect_system() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    case "$os" in
        linux) OS="linux" ;;
        darwin) OS="macos" ;;
        *) fatal "Unsupported OS: $os" ;;
    esac

    case "$arch" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) fatal "Unsupported architecture: $arch" ;;
    esac

    success "Detected: $OS ($ARCH)"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install Docker
check_docker() {
    info "Checking Docker installation..."

    if command_exists docker; then
        if docker info >/dev/null 2>&1; then
            local version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
            success "Docker $version is installed and running"
            return 0
        else
            warning "Docker is installed but not running"
            info "Starting Docker..."
            if [ "$EUID" -eq 0 ]; then
                systemctl start docker || fatal "Failed to start Docker"
            else
                fatal "Please start Docker manually (requires sudo)"
            fi
        fi
    else
        warning "Docker is not installed"
        echo ""
        read -p "Would you like to install Docker? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_docker
        else
            fatal "Docker is required. Please install it manually: https://docs.docker.com/get-docker/"
        fi
    fi
}

# Install Docker
install_docker() {
    info "Installing Docker..."

    case "$OS" in
        linux)
            if command_exists apt-get; then
                # Debian/Ubuntu
                info "Detected Debian/Ubuntu system"
                if [ "$EUID" -ne 0 ]; then
                    fatal "Docker installation requires root. Run: curl -fsSL https://get.docker.com | sudo sh"
                fi
                curl -fsSL https://get.docker.com | sh
                systemctl enable docker
                systemctl start docker
                usermod -aG docker "$SUDO_USER" || true
            elif command_exists yum; then
                # RHEL/CentOS
                info "Detected RHEL/CentOS system"
                if [ "$EUID" -ne 0 ]; then
                    fatal "Docker installation requires root"
                fi
                curl -fsSL https://get.docker.com | sh
                systemctl enable docker
                systemctl start docker
            else
                fatal "Could not determine package manager. Install Docker manually: https://docs.docker.com/get-docker/"
            fi
            ;;
        macos)
            fatal "Please install Docker Desktop from: https://docs.docker.com/desktop/mac/install/"
            ;;
    esac

    success "Docker installed successfully"
    warning "You may need to log out and back in for Docker group changes to take effect"
}

# Check Docker Compose
check_docker_compose() {
    info "Checking Docker Compose..."

    if command_exists docker-compose || docker compose version >/dev/null 2>&1; then
        success "Docker Compose is available"
        return 0
    else
        warning "Docker Compose not found"
        if docker compose version >/dev/null 2>&1; then
            success "Docker Compose plugin is available"
        else
            fatal "Docker Compose is required but not installed"
        fi
    fi
}

# Check other dependencies
check_dependencies() {
    info "Checking dependencies..."

    local missing=()

    for cmd in curl wget jq git; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warning "Missing dependencies: ${missing[*]}"
        echo ""
        read -p "Install missing dependencies? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_dependencies "${missing[@]}"
        else
            fatal "Required dependencies missing: ${missing[*]}"
        fi
    else
        success "All dependencies installed"
    fi
}

# Install system dependencies
install_dependencies() {
    local deps=("$@")
    info "Installing: ${deps[*]}"

    case "$OS" in
        linux)
            if command_exists apt-get; then
                if [ "$EUID" -eq 0 ]; then
                    apt-get update && apt-get install -y "${deps[@]}"
                else
                    sudo apt-get update && sudo apt-get install -y "${deps[@]}"
                fi
            elif command_exists yum; then
                if [ "$EUID" -eq 0 ]; then
                    yum install -y "${deps[@]}"
                else
                    sudo yum install -y "${deps[@]}"
                fi
            fi
            ;;
        macos)
            if command_exists brew; then
                brew install "${deps[@]}"
            else
                fatal "Homebrew not found. Install from: https://brew.sh/"
            fi
            ;;
    esac

    success "Dependencies installed"
}

# Download vNode
download_vnode() {
    info "Downloading vNode..."

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$INSTANCES_DIR"

    # Clone or download repository
    if [ -d "$INSTALL_DIR/.git" ]; then
        info "Updating existing installation..."
        cd "$INSTALL_DIR"
        git pull
    else
        info "Downloading from GitHub..."
        # For curl-based install, download archive
        if [ -n "${GITHUB_REPO:-}" ]; then
            local temp_dir=$(mktemp -d)
            cd "$temp_dir"
            curl -fsSL "https://github.com/$GITHUB_REPO/archive/refs/heads/main.tar.gz" | tar xz
            cp -r vnode-main/* "$INSTALL_DIR/"
            cd /
            rm -rf "$temp_dir"
        else
            # Fallback: assume we're running from the repo
            local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            cp -r "$script_dir"/* "$INSTALL_DIR/"
        fi
    fi

    # Make scripts executable
    chmod +x "$INSTALL_DIR"/scripts/*.sh

    success "vNode downloaded to $INSTALL_DIR"
}

# Install CLI wrapper
install_cli() {
    info "Installing vNode CLI..."

    if [ ! -f "$INSTALL_DIR/vnode" ]; then
        warning "CLI not found, skipping"
        return
    fi

    # Ensure bin directory exists
    if [ "$EUID" -eq 0 ]; then
        mkdir -p "$BIN_DIR"
        cp "$INSTALL_DIR/vnode" "$BIN_DIR/vnode"
        chmod +x "$BIN_DIR/vnode"
    else
        mkdir -p "$BIN_DIR"
        cp "$INSTALL_DIR/vnode" "$BIN_DIR/vnode"
        chmod +x "$BIN_DIR/vnode"
    fi

    success "vNode CLI installed to $BIN_DIR/vnode"
}

# Create config
create_config() {
    info "Creating configuration..."

    cat > "$CONFIG_DIR/config" << EOF
# vNode Configuration
INSTALL_DIR="$INSTALL_DIR"
INSTANCES_DIR="$INSTANCES_DIR"
CONFIG_DIR="$CONFIG_DIR"
VERSION="$VNODE_VERSION"
EOF

    chmod 600 "$CONFIG_DIR/config"
    success "Configuration created at $CONFIG_DIR/config"
}

# Check if already installed
check_existing() {
    if [ -d "$INSTALL_DIR" ] && [ -f "$BIN_DIR/vnode" ]; then
        warning "vNode is already installed"

        # If running non-interactively (piped to bash), auto-upgrade
        if [ ! -t 0 ]; then
            info "Running in non-interactive mode - upgrading automatically"
            return 0
        fi

        echo ""
        read -p "Reinstall/upgrade? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi
}

# Post-install message
show_completion() {
    echo ""
    success "vNode installed successfully!"
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    echo -e "  ${CYAN}vnode create${NC}              - Create a new vNode instance"
    echo -e "  ${CYAN}vnode list${NC}                - List all instances"
    echo -e "  ${CYAN}vnode status <name>${NC}       - Check instance status"
    echo -e "  ${CYAN}vnode help${NC}                - Show all commands"
    echo ""
    echo -e "${BOLD}Files:${NC}"
    echo -e "  Install dir:   ${INSTALL_DIR}"
    echo -e "  Config:        ${CONFIG_DIR}"
    echo -e "  Instances:     ${INSTANCES_DIR}"
    echo -e "  CLI:           ${BIN_DIR}/vnode"
    echo ""
    echo -e "${BOLD}Documentation:${NC}"
    echo -e "  README:        ${INSTALL_DIR}/README.md"
    echo -e "  Guide:         ${INSTALL_DIR}/GUIDE.md"
    echo -e "  Advanced:      ${INSTALL_DIR}/ADVANCED.md"
    echo ""

    if [ "$EUID" -ne 0 ]; then
        if ! groups | grep -q docker; then
            warning "Your user is not in the docker group"
            echo "  Run: sudo usermod -aG docker \$USER"
            echo "  Then log out and back in"
            echo ""
        fi

        if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
            warning "~/.local/bin is not in your PATH"
            echo "  Add this to your ~/.bashrc or ~/.zshrc:"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
        fi
    fi
}

# Uninstall function
uninstall() {
    warning "This will remove vNode and all instances"
    read -p "Are you sure? (type 'yes' to confirm) " -r
    echo
    if [[ $REPLY == "yes" ]]; then
        info "Uninstalling vNode..."
        rm -f "$BIN_DIR/vnode"
        rm -rf "$INSTALL_DIR"
        rm -rf "$CONFIG_DIR"
        read -p "Remove all instance data at $INSTANCES_DIR? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTANCES_DIR"
        fi
        success "vNode uninstalled"
    else
        info "Uninstall cancelled"
    fi
}

# Main installation flow
main() {
    # Check for uninstall flag
    if [ "${1:-}" = "uninstall" ]; then
        uninstall
        exit 0
    fi

    show_banner
    check_root
    detect_system
    check_existing

    echo ""
    info "Starting installation..."
    echo ""

    check_docker
    check_docker_compose
    check_dependencies
    download_vnode
    install_cli
    create_config

    show_completion
}

main "$@"
