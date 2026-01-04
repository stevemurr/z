#!/bin/bash
# Z - Unified shell tools installer
# Usage: curl -fsSL https://raw.githubusercontent.com/[you]/z/main/install.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
Z_PLUGIN_DIR="${HOME}/.config/zsh/plugins/z"
Z_DATA_DIR="${HOME}/.z"
Z_REPO="https://github.com/stevemurr/z.git"

# Functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check for zsh
check_zsh() {
    if ! command -v zsh &> /dev/null; then
        error "zsh is not installed. Please install zsh first."
    fi
    success "zsh found"
}

# Check for git
check_git() {
    if ! command -v git &> /dev/null; then
        error "git is not installed. Please install git first."
    fi
    success "git found"
}

# Download/update z plugin
install_plugin() {
    info "Installing z plugin..."

    # Create plugins directory if needed
    mkdir -p "$(dirname "${Z_PLUGIN_DIR}")"

    if [[ -d "${Z_PLUGIN_DIR}" ]]; then
        info "z plugin directory exists, updating..."
        cd "${Z_PLUGIN_DIR}"
        git pull --quiet 2>/dev/null || warn "Could not update (maybe not a git repo)"
        cd - > /dev/null
    else
        info "Cloning z plugin..."
        if git clone --quiet "${Z_REPO}" "${Z_PLUGIN_DIR}"; then
            success "Cloned z plugin"
        else
            # Fallback: create directory structure manually
            warn "Could not clone from git, creating structure manually..."
            mkdir -p "${Z_PLUGIN_DIR}"/{lib,modules,completions}
            echo "# Z plugin - created manually" > "${Z_PLUGIN_DIR}/z.plugin.zsh"
            warn "Please manually copy z plugin files to ${Z_PLUGIN_DIR}"
        fi
    fi

    success "z plugin installed at ${Z_PLUGIN_DIR}"
}

# Initialize z data directory
init_data_dir() {
    info "Initializing z data directory..."

    # Create directories
    mkdir -p "${Z_DATA_DIR}"/{env,path,alias,app/bin,app/metadata,modules,sys}

    # Create config file
    if [[ ! -f "${Z_DATA_DIR}/config.zsh" ]]; then
        cat > "${Z_DATA_DIR}/config.zsh" <<'EOF'
# Z configuration
# Enabled modules
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(env path alias app bench sys modules)
EOF
        success "Created config file"
    fi

    # Create empty data files
    [[ ! -f "${Z_DATA_DIR}/env/vars.zsh" ]] && echo "# Managed by z env" > "${Z_DATA_DIR}/env/vars.zsh"
    [[ ! -f "${Z_DATA_DIR}/path/paths.zsh" ]] && echo "# Managed by z path" > "${Z_DATA_DIR}/path/paths.zsh"
    [[ ! -f "${Z_DATA_DIR}/alias/aliases.zsh" ]] && echo "# Managed by z alias" > "${Z_DATA_DIR}/alias/aliases.zsh"

    success "z data directory initialized at ${Z_DATA_DIR}"
}

# Add z to .zshrc
add_to_zshrc() {
    local zshrc="${HOME}/.zshrc"
    local source_line="source \"${Z_PLUGIN_DIR}/z.plugin.zsh\""

    info "Configuring .zshrc..."

    # Check if already added
    if grep -q "z.plugin.zsh" "${zshrc}" 2>/dev/null; then
        warn "z plugin already in .zshrc"
        return
    fi

    # Backup .zshrc
    if [[ -f "${zshrc}" ]]; then
        cp "${zshrc}" "${zshrc}.backup.$(date +%Y%m%d%H%M%S)"
        success "Backed up .zshrc"
    fi

    # Add source line
    cat >> "${zshrc}" <<EOF

# Z - Unified shell tools
${source_line}
EOF

    success "Added z plugin to .zshrc"
}

# Setup machine name (for multi-machine support)
setup_machine() {
    local machine_name=""

    # Get hostname as default
    local default_name
    default_name=$(hostname -s 2>/dev/null || echo "localhost")

    echo ""
    info "Multi-machine setup (optional)"
    echo "    This allows you to query/sync env vars, paths, and aliases"
    echo "    across multiple machines using Tailscale or SSH."
    echo ""

    # Only prompt if interactive
    if [[ -t 0 ]]; then
        read -p "Enter a name for this machine [${default_name}]: " machine_name
        machine_name="${machine_name:-${default_name}}"

        # Create machines.json
        mkdir -p "${Z_DATA_DIR}/sys"
        cat > "${Z_DATA_DIR}/sys/machines.json" <<EOF
{
  "this_machine": "${machine_name}",
  "machines": []
}
EOF
        success "Machine configured as: ${machine_name}"
    else
        info "Run 'z sys init' to set up multi-machine support"
    fi
}

# Main
main() {
    echo ""
    echo "=================================="
    echo "  Z - Unified Shell Tools"
    echo "  Installer"
    echo "=================================="
    echo ""

    check_zsh
    check_git
    install_plugin
    init_data_dir
    add_to_zshrc
    setup_machine

    echo ""
    echo "=================================="
    success "Installation complete!"
    echo "=================================="
    echo ""
    echo "To get started:"
    echo "  1. Restart your shell or run: source ~/.zshrc"
    echo "  2. Run: z"
    echo ""
    echo "Quick start:"
    echo "  z env add API_KEY \"your-key\" -s    # Add secret env var"
    echo "  z path add golang \"\$HOME/go/bin\"   # Add path entry"
    echo "  z alias add k kubectl              # Add alias"
    echo "  z modules                          # List modules"
    echo ""
    echo "Multi-machine (optional):"
    echo "  z sys init                         # Set machine name"
    echo "  z sys add work myserver.example.com  # Add remote machine"
    echo "  z env list -m work                 # List env from remote"
    echo ""
}

main "$@"
