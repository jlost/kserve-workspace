#!/bin/bash
# Install development dependencies for the KServe VS Code workspace on Fedora
# Preference order: official dnf repo > unofficial dnf repo > rpm > AppImage > uv tool install > curl | sh

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root. It will use sudo when needed."
   exit 1
fi

# Get current username
CURRENT_USER="${USER:-$(whoami)}"
SHELL_CONFIG="$HOME/.zshenv"

# Update system
log_info "Updating system packages..."
sudo dnf -y update

# Install zsh if not present
if ! command -v zsh &> /dev/null; then
    log_info "Installing zsh..."
    sudo dnf -y install zsh
fi

# Set zsh as default shell
if [[ "$SHELL" != *"zsh"* ]]; then
    log_info "Setting zsh as default shell..."
    # Try sss_override first (for systems with sssd)
    if command -v sss_override &> /dev/null; then
        sudo sss_override user-add "$CURRENT_USER" --shell /bin/zsh || {
            log_warn "sss_override failed, trying usermod..."
            sudo usermod --shell /bin/zsh "$CURRENT_USER"
        }
    else
        # Use usermod (non-interactive) instead of chsh
        sudo usermod --shell /bin/zsh "$CURRENT_USER"
    fi
    log_info "Default shell changed to zsh. Please log out and back in for it to take effect."
fi

# Install basic dependencies that might be needed
log_info "Installing basic dependencies..."
sudo dnf -y install curl wget git

# Function to install from official DNF repo
# Tries to install directly - fails gracefully if package not available
install_from_dnf() {
    local package=$1
    if sudo dnf -y install "$package" 2>/dev/null; then
        log_info "Installed $package from official DNF repository"
        return 0
    fi
    return 1
}

# Function to add unofficial DNF repo and install
install_from_unofficial_repo() {
    local repo_name=$1
    local repo_url=$2
    local gpg_key_url=$3
    local package=$4
    local repo_file="/etc/yum.repos.d/${repo_name}.repo"
    
    # Check if repo already exists
    if [[ -f "$repo_file" ]]; then
        log_info "Repository $repo_name already exists, skipping setup..."
    else
        log_info "Adding unofficial DNF repository for $package..."
        if [[ -n "$gpg_key_url" ]]; then
            sudo rpm --import "$gpg_key_url" || true
        fi
        
        # Check if URL is a .repo file or a base URL
        if [[ "$repo_url" == *.repo ]]; then
            # For .repo files, use --from-repofile (DNF 5 syntax)
            sudo dnf config-manager addrepo --from-repofile="$repo_url" 2>/dev/null || {
                log_warn "Failed to add repo via dnf config-manager, creating repo file manually..."
                # Fallback: download .repo file and place it manually
                curl -sSL "$repo_url" | sudo tee "$repo_file" > /dev/null
            }
        else
            # For base URLs, create repo file manually
            sudo tee "$repo_file" > /dev/null <<EOF
[${repo_name}]
name=${repo_name}
baseurl=${repo_url}
enabled=1
gpgcheck=1
EOF
            if [[ -n "$gpg_key_url" ]]; then
                echo "gpgkey=${gpg_key_url}" | sudo tee -a "$repo_file" > /dev/null
            fi
        fi
    fi
    sudo dnf -y install "$package"
}

# Function to install from RPM
install_from_rpm() {
    local rpm_url=$1
    local package_name=$2
    log_info "Installing $package_name from RPM..."
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    curl -L -o "${package_name}.rpm" "$rpm_url"
    sudo dnf -y install "./${package_name}.rpm"
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Function to install AppImage
install_from_appimage() {
    local appimage_url=$1
    local binary_name=$2
    local install_path=${3:-/usr/local/bin}
    log_info "Installing $binary_name from AppImage..."
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    curl -L -o "${binary_name}.AppImage" "$appimage_url"
    chmod +x "${binary_name}.AppImage"
    sudo mv "${binary_name}.AppImage" "${install_path}/${binary_name}"
    cd - > /dev/null
    rm -rf "$temp_dir"
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

# Install kubectl
log_info "=== Installing kubectl ==="
if command -v kubectl &> /dev/null; then
    log_info "kubectl already installed"
elif sudo dnf -y install kubectl 2>/dev/null; then
    log_info "Installed kubectl from official DNF repository"
elif sudo dnf -y install kubernetes-client 2>/dev/null; then
    log_info "Installed kubectl (kubernetes-client) from official DNF repository"
else
    log_info "kubectl not in official repos, adding Kubernetes repository..."
    if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
        sudo rpm --import https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key || true
        sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
EOF
    fi
    sudo dnf -y install kubectl
fi

# Install oc (OpenShift CLI)
log_info "=== Installing oc (OpenShift CLI) ==="
if ! command -v oc &> /dev/null; then
    if ! install_from_dnf "openshift-clients"; then
        log_info "oc not in official repos, installing from OpenShift mirror..."
        # oc is distributed as a tar.gz, not RPM
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        curl -L -o oc.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz"
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
    if ! install_from_dnf "crc"; then
        log_info "crc not in official repos, installing from tarball..."
        # CRC is distributed as a tarball
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        curl -L -o crc-installer.tar.xz "https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/crc-linux-amd64.tar.xz"
        tar -xf crc-installer.tar.xz
        sudo mv crc-linux-*/crc /usr/local/bin/
        cd - > /dev/null
        rm -rf "$temp_dir"
    fi
else
    log_info "crc already installed"
fi

# Install golang
log_info "=== Installing golang ==="
install_from_dnf "golang" || install_from_dnf "go"

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
install_from_dnf "python3.11" || install_from_dnf "python311"

# Install uv
log_info "=== Installing uv ==="
if ! install_from_dnf "uv"; then
    log_info "uv not in official repos, installing via uv tool installer..."
    install_via_curl_sh "https://astral.sh/uv/install.sh" "uv"
    # Ensure it's in PATH (idempotent - check if already exists)
    if [[ -d "$HOME/.cargo/bin" ]] && ! grep -q ".cargo/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> "$SHELL_CONFIG"
    fi
    if [[ -d "$HOME/.local/bin" ]] && ! grep -q ".local/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_CONFIG"
    fi
fi

# Install openssl
log_info "=== Installing openssl ==="
install_from_dnf "openssl"

# Install podman
log_info "=== Installing podman ==="
install_from_dnf "podman"

# Install kind (Kubernetes in Docker) - pulls in moby-engine as dependency
log_info "=== Installing kind ==="
install_from_dnf "kind"

# Enable and start Docker service (installed as kind dependency)
log_info "=== Enabling and starting Docker service ==="
if systemctl is-active --quiet docker; then
    log_info "Docker service is already running"
else
    sudo systemctl enable docker
    sudo systemctl start docker
    log_info "Docker service enabled and started"
fi

# Add user to docker group (to run docker without sudo)
if ! groups "$CURRENT_USER" | grep -q docker; then
    log_info "Adding $CURRENT_USER to docker group..."
    sudo usermod -aG docker "$CURRENT_USER"
    log_warn "You may need to log out and back in for docker group membership to take effect"
else
    log_info "User $CURRENT_USER is already in docker group"
fi

# Install yq
log_info "=== Installing yq ==="
if ! install_from_dnf "yq"; then
    if command -v go &> /dev/null; then
        log_info "Installing yq via go install..."
        go install github.com/mikefarah/yq/v4@latest
        # Ensure go/bin is in PATH (idempotent - check if already exists)
        if [[ -d "$HOME/go/bin" ]] && ! grep -q "go/bin" "$SHELL_CONFIG" 2>/dev/null; then
            echo "export PATH=\"\$HOME/go/bin:\$PATH\"" >> "$SHELL_CONFIG"
        fi
    else
        log_warn "yq not available via dnf and go not available, skipping..."
    fi
fi

# Install jq
log_info "=== Installing jq ==="
install_from_dnf "jq"

# Install envsubst (part of gettext)
log_info "=== Installing envsubst (gettext) ==="
install_from_dnf "gettext"

# Install devspace
log_info "=== Installing devspace ==="
if ! command -v devspace &> /dev/null; then
    if ! install_from_dnf "devspace"; then
        log_info "devspace not in official repos, installing from GitHub releases..."
        # Download latest devspace binary from GitHub releases
        temp_dir=$(mktemp -d)
        cd "$temp_dir"
        devspace_version=$(curl -s https://api.github.com/repos/devspace-sh/devspace/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 | sed 's/^v//')
        devspace_url="https://github.com/devspace-sh/devspace/releases/download/v${devspace_version}/devspace-linux-amd64"
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
    log_info "Installing Cursor from repository..."
    if ! install_from_dnf "cursor"; then
        log_info "Cursor not in official repos, adding Cursor repository..."
        # Use official Cursor repository (https://cursor.com/docs/downloads)
        install_from_unofficial_repo \
            "cursor" \
            "https://downloads.cursor.com/yumrepo" \
            "https://downloads.cursor.com/keys/anysphere.asc" \
            "cursor"
    fi
else
    log_info "Cursor already installed"
fi

# Install brave-browser
log_info "=== Installing brave-browser ==="
if ! install_from_dnf "brave-browser"; then
    log_info "brave-browser not in official repos, adding Brave repository..."
    install_from_unofficial_repo \
        "brave-browser" \
        "https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo" \
        "https://brave-browser-rpm-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
        "brave-browser"
fi

# Set BROWSER environment variable if not set (idempotent - check if already exists)
if [[ -z "${BROWSER:-}" ]] && ! grep -q "export BROWSER=" "$SHELL_CONFIG" 2>/dev/null; then
    log_info "Setting BROWSER environment variable to brave-browser..."
    echo "export BROWSER=brave-browser" >> "$SHELL_CONFIG"
fi

# Source the shell config to make variables available in current session
if [[ -f "$SHELL_CONFIG" ]]; then
    log_info "Sourcing $SHELL_CONFIG to make variables available..."
    # shellcheck source=/dev/null
    source "$SHELL_CONFIG"
fi

log_info "=== Installation complete! ==="
log_info "Please restart your shell or run: source $SHELL_CONFIG"
log_info "To verify installations, check that all tools are in your PATH:"
log_info "  cursor, oc, kubectl, crc, go, dlv, python3.11, uv, openssl, podman, docker, kind, yq, jq, envsubst, devspace, ko, brave-browser"
log_info ""
log_info "Note: You may need to log out and back in for:"
log_info "  - zsh to become your default shell"
log_info "  - docker group membership to take effect (run docker without sudo)"

