#!/bin/bash
# Install development dependencies for the KServe VS Code workspace on macOS
# Preference order: Homebrew > Homebrew Cask > direct download > uv tool install > curl | sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script is designed for macOS only"
    exit 1
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root. It will use sudo when needed."
   exit 1
fi

# Get current username
CURRENT_USER="${USER:-$(whoami)}"
SHELL_CONFIG="$HOME/.zshrc"

# Check for Homebrew and install if not present
log_info "Checking for Homebrew..."
if ! command -v brew &> /dev/null; then
    log_info "Homebrew not found, installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        if ! grep -q "/opt/homebrew/bin" "$SHELL_CONFIG" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_CONFIG"
        fi
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        if ! grep -q "/usr/local/bin" "$SHELL_CONFIG" 2>/dev/null; then
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$SHELL_CONFIG"
        fi
    fi
else
    log_info "Homebrew already installed"
    # Ensure Homebrew is in PATH
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Update Homebrew
log_info "Updating Homebrew..."
brew update

# Install zsh if not present (should already be on macOS, but check anyway)
if ! command -v zsh &> /dev/null; then
    log_info "Installing zsh..."
    brew install zsh
fi

# Set zsh as default shell (macOS already uses zsh by default, but ensure it)
if [[ "$SHELL" != *"zsh"* ]]; then
    log_info "Setting zsh as default shell..."
    chsh -s "$(which zsh)"
    log_info "Default shell changed to zsh. Please log out and back in for it to take effect."
fi

# Install basic dependencies
log_info "Installing basic dependencies..."
brew install curl wget git

# Function to install from Homebrew
install_from_brew() {
    local package=$1
    if brew list "$package" &>/dev/null; then
        log_info "$package already installed via Homebrew"
        return 0
    elif brew install "$package" 2>/dev/null; then
        log_info "Installed $package from Homebrew"
        return 0
    fi
    return 1
}

# Function to install from Homebrew Cask (for GUI applications)
install_from_brew_cask() {
    local package=$1
    if brew list --cask "$package" &>/dev/null; then
        log_info "$package already installed via Homebrew Cask"
        return 0
    elif brew install --cask "$package" 2>/dev/null; then
        log_info "Installed $package from Homebrew Cask"
        return 0
    fi
    return 1
}

# Function to install via uv tool
install_via_uv() {
    local package=$1
    log_info "Installing $package via uv tool..."
    uv tool install "$package"
}

# Function to install via curl | sh
install_via_curl_sh() {
    local script_url=$1
    local package_name=$2
    log_warn "Installing $package_name via curl | sh (less secure method)..."
    curl -sSL "$script_url" | sh
}

# Function to install binary from GitHub releases
install_from_github_release() {
    local repo=$1
    local binary_name=$2
    local install_path=${3:-/usr/local/bin}
    log_info "Installing $binary_name from GitHub releases..."
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    local version
    version=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 | sed 's/^v//')
    local url="https://github.com/${repo}/releases/download/v${version}/${binary_name}-darwin-amd64"
    # Try arm64 for Apple Silicon Macs
    if [[ "$(uname -m)" == "arm64" ]]; then
        url="https://github.com/${repo}/releases/download/v${version}/${binary_name}-darwin-arm64"
    fi
    curl -L -o "$binary_name" "$url" || {
        log_warn "Failed to download arm64 version, trying amd64..."
        url="https://github.com/${repo}/releases/download/v${version}/${binary_name}-darwin-amd64"
        curl -L -o "$binary_name" "$url"
    }
    chmod +x "$binary_name"
    sudo mv "$binary_name" "${install_path}/${binary_name}"
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Install kubectl
log_info "=== Installing kubectl ==="
if command -v kubectl &> /dev/null; then
    log_info "kubectl already installed"
elif install_from_brew "kubectl"; then
    : # Success
else
    log_error "Failed to install kubectl"
fi

# Install oc (OpenShift CLI)
log_info "=== Installing oc (OpenShift CLI) ==="
if ! command -v oc &> /dev/null; then
    if ! install_from_brew "openshift-cli"; then
        log_info "oc not in Homebrew, installing from OpenShift mirror..."
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        # Detect architecture
        if [[ "$(uname -m)" == "arm64" ]]; then
            oc_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-mac-arm64.tar.gz"
        else
            oc_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-mac.tar.gz"
        fi
        curl -L -o oc.tar.gz "$oc_url"
        tar -xzf oc.tar.gz
        sudo mv oc /usr/local/bin/
        # Don't overwrite kubectl if it's already installed
        if [[ -f kubectl ]] && ! command -v kubectl &> /dev/null; then
            sudo mv kubectl /usr/local/bin/
        fi
        cd - > /dev/null
        rm -rf "$temp_dir"
    fi
else
    log_info "oc already installed"
fi

# Install crc (OpenShift Local)
log_info "=== Installing crc (OpenShift Local) ==="
if ! command -v crc &> /dev/null; then
    if ! install_from_brew "crc"; then
        log_info "crc not in Homebrew, installing from tarball..."
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        # Detect architecture
        if [[ "$(uname -m)" == "arm64" ]]; then
            crc_url="https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/crc-macos-arm64-installer.tar.xz"
        else
            crc_url="https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/crc-macos-amd64-installer.tar.xz"
        fi
        curl -L -o crc-installer.tar.xz "$crc_url"
        tar -xf crc-installer.tar.xz
        sudo mv crc-*/crc /usr/local/bin/
        cd - > /dev/null
        rm -rf "$temp_dir"
    fi
else
    log_info "crc already installed"
fi

# Install golang
log_info "=== Installing golang ==="
install_from_brew "go"

# Install dlv (delve debugger) - requires golang
log_info "=== Installing dlv (delve) ==="
if command -v go &> /dev/null; then
    log_info "Installing dlv via go install..."
    go install github.com/go-delve/delve/cmd/dlv@latest
    # Ensure it's in PATH (idempotent - check if already exists)
    if [[ -d "$HOME/go/bin" ]] && ! grep -q "go/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo "export PATH=\"\$HOME/go/bin:\$PATH\"" >> "$SHELL_CONFIG"
    fi
else
    log_error "golang not found, cannot install dlv"
fi

# Install python3.11
log_info "=== Installing python3.11 ==="
install_from_brew "python@3.11"

# Install uv
log_info "=== Installing uv ==="
if command -v uv &> /dev/null; then
    log_info "uv already installed"
else
    log_info "Installing uv via uv tool installer..."
    install_via_curl_sh "https://astral.sh/uv/install.sh" "uv"
    # Ensure it's in PATH (idempotent - check if already exists)
    if [[ -d "$HOME/.cargo/bin" ]] && ! grep -q ".cargo/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> "$SHELL_CONFIG"
    fi
    if [[ -d "$HOME/.local/bin" ]] && ! grep -q ".local/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_CONFIG"
    fi
fi

# Install openssl (macOS has an old version, Homebrew provides newer one)
log_info "=== Installing openssl ==="
install_from_brew "openssl"

# Install podman
log_info "=== Installing podman ==="
install_from_brew "podman"

# Install kind (Kubernetes in Docker)
log_info "=== Installing kind ==="
install_from_brew "kind"

# Install cloud-provider-kind (LoadBalancer support for Kind clusters)
log_info "=== Installing cloud-provider-kind ==="
if command -v go &> /dev/null; then
    log_info "Installing cloud-provider-kind via go install..."
    go install sigs.k8s.io/cloud-provider-kind@latest
else
    log_error "golang not found, cannot install cloud-provider-kind"
fi

# Install Docker Desktop or Docker CLI
log_info "=== Installing Docker ==="
if command -v docker &> /dev/null; then
    log_info "Docker already installed"
elif install_from_brew_cask "docker"; then
    log_info "Docker Desktop installed. Please start Docker Desktop from Applications."
elif install_from_brew "docker"; then
    log_info "Docker CLI installed"
else
    log_warn "Docker installation failed. You may need to install Docker Desktop manually from https://www.docker.com/products/docker-desktop"
fi

# Install yq
log_info "=== Installing yq ==="
if ! install_from_brew "yq"; then
    if command -v go &> /dev/null; then
        log_info "Installing yq via go install..."
        go install github.com/mikefarah/yq/v4@latest
        # Ensure go/bin is in PATH (idempotent - check if already exists)
        if [[ -d "$HOME/go/bin" ]] && ! grep -q "go/bin" "$SHELL_CONFIG" 2>/dev/null; then
            echo "export PATH=\"\$HOME/go/bin:\$PATH\"" >> "$SHELL_CONFIG"
        fi
    else
        log_warn "yq not available via Homebrew and go not available, skipping..."
    fi
fi

# Install jq
log_info "=== Installing jq ==="
install_from_brew "jq"

# Install envsubst (part of gettext)
log_info "=== Installing envsubst (gettext) ==="
install_from_brew "gettext"

# Install devspace
log_info "=== Installing devspace ==="
if ! command -v devspace &> /dev/null; then
    if ! install_from_brew "devspace"; then
        log_info "devspace not in Homebrew, installing from GitHub releases..."
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        devspace_version=$(curl -s https://api.github.com/repos/devspace-sh/devspace/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 | sed 's/^v//')
        # Detect architecture
        if [[ "$(uname -m)" == "arm64" ]]; then
            devspace_url="https://github.com/devspace-sh/devspace/releases/download/v${devspace_version}/devspace-darwin-arm64"
        else
            devspace_url="https://github.com/devspace-sh/devspace/releases/download/v${devspace_version}/devspace-darwin-amd64"
        fi
        curl -L -o devspace "$devspace_url"
        chmod +x devspace
        sudo mv devspace /usr/local/bin/
        cd - > /dev/null
        rm -rf "$temp_dir"
    fi
else
    log_info "devspace already installed"
fi

# Install ko
log_info "=== Installing ko ==="
if command -v go &> /dev/null; then
    log_info "Installing ko via go install..."
    go install github.com/google/ko@latest
    # Ensure go/bin is in PATH (idempotent - check if already exists)
    if [[ -d "$HOME/go/bin" ]] && ! grep -q "go/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo "export PATH=\"\$HOME/go/bin:\$PATH\"" >> "$SHELL_CONFIG"
    fi
else
    log_error "golang not found, cannot install ko"
fi

# Install Cursor
log_info "=== Installing Cursor ==="
if ! command -v cursor &> /dev/null; then
    if ! install_from_brew_cask "cursor"; then
        log_info "Cursor not in Homebrew Cask, downloading from official site..."
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        # Download Cursor .dmg
        cursor_dmg_url="https://downloader.cursor.sh/mac"
        curl -L -o cursor.dmg "$cursor_dmg_url"
        # Mount the DMG
        hdiutil attach cursor.dmg -nobrowse -quiet
        # Copy Cursor.app to Applications
        sudo cp -R /Volumes/Cursor/Cursor.app /Applications/
        # Unmount the DMG
        hdiutil detach /Volumes/Cursor -quiet
        cd - > /dev/null
        rm -rf "$temp_dir"
        log_info "Cursor installed. You can launch it from Applications."
    fi
else
    log_info "Cursor already installed"
fi

# Install brave-browser
log_info "=== Installing brave-browser ==="
if ! install_from_brew_cask "brave-browser"; then
    log_warn "brave-browser installation failed. You may need to install it manually from https://brave.com"
fi

# Set BROWSER environment variable if not set (idempotent - check if already exists)
if [[ -z "${BROWSER:-}" ]] && ! grep -q "export BROWSER=" "$SHELL_CONFIG" 2>/dev/null; then
    log_info "Setting BROWSER environment variable to brave-browser..."
    echo "export BROWSER=brave-browser" >> "$SHELL_CONFIG"
fi

# Source the shell config to make variables available in current session
if [[ -f "$SHELL_CONFIG" ]]; then
    log_info "Sourcing $SHELL_CONFIG to make variables available..."
    # Use zsh to source zsh config files (zstyle and other zsh-specific commands won't work in bash)
    if [[ "$SHELL_CONFIG" == *".zshrc"* ]] || [[ "$SHELL_CONFIG" == *".zshenv"* ]]; then
        if command -v zsh &> /dev/null; then
            zsh -c "source $SHELL_CONFIG" || log_warn "Failed to source $SHELL_CONFIG (this is okay, variables will be available after shell restart)"
        else
            log_warn "zsh not available, skipping sourcing of zsh config file"
        fi
    else
        # shellcheck source=/dev/null
        source "$SHELL_CONFIG"
    fi
fi

log_info "=== Installation complete! ==="
log_info "Please restart your shell or run: source $SHELL_CONFIG"
log_info "To verify installations, check that all tools are in your PATH:"
log_info "  cursor, oc, kubectl, crc, go, dlv, python3.11, uv, openssl, podman, docker, kind, yq, jq, envsubst, devspace, ko, brave-browser"
log_info ""
log_info "Note: You may need to:"
log_info "  - Restart your shell for PATH changes to take effect"
log_info "  - Start Docker Desktop from Applications if you installed it"
log_info "  - Log out and back in for zsh to become your default shell (if changed)"
