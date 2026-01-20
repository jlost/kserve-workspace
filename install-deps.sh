#!/bin/bash
# Install development dependencies for the KServe VS Code workspace
# This script detects the OS and calls the appropriate platform-specific installer

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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect OS
OS_TYPE=""
DISTRO=""

if [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
    log_info "Detected macOS"
elif [[ "$(uname)" == "Linux" ]]; then
    OS_TYPE="linux"
    # Try to detect Linux distribution
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="$ID"
        log_info "Detected Linux distribution: $DISTRO"
    else
        log_warn "Could not detect Linux distribution, assuming Fedora-compatible"
        DISTRO="fedora"
    fi
else
    log_error "Unsupported operating system: $(uname)"
    exit 1
fi

# Determine which installer script to use
INSTALLER_SCRIPT=""

if [[ "$OS_TYPE" == "macos" ]]; then
    INSTALLER_SCRIPT="${SCRIPT_DIR}/install-macos-deps.sh"
elif [[ "$OS_TYPE" == "linux" ]]; then
    # Check if it's a Fedora-based distribution (Fedora, RHEL, CentOS Stream, etc.)
    if [[ "$DISTRO" == "fedora" ]] || [[ "$DISTRO" == "rhel" ]] || [[ "$DISTRO" == "centos" ]] || [[ "$DISTRO" == "rocky" ]] || [[ "$DISTRO" == "almalinux" ]]; then
        INSTALLER_SCRIPT="${SCRIPT_DIR}/install-fedora-deps.sh"
    else
        log_warn "Distribution '$DISTRO' may not be fully supported."
        log_warn "Attempting to use Fedora installer (uses dnf package manager)..."
        INSTALLER_SCRIPT="${SCRIPT_DIR}/install-fedora-deps.sh"
    fi
else
    log_error "Could not determine appropriate installer script"
    exit 1
fi

# Check if the installer script exists
if [[ ! -f "$INSTALLER_SCRIPT" ]]; then
    log_error "Installer script not found: $INSTALLER_SCRIPT"
    exit 1
fi

# Make sure the installer script is executable
if [[ ! -x "$INSTALLER_SCRIPT" ]]; then
    log_info "Making installer script executable..."
    chmod +x "$INSTALLER_SCRIPT"
fi

# Run the appropriate installer script
log_info "Running installer script: $INSTALLER_SCRIPT"
log_info "=========================================="
exec "$INSTALLER_SCRIPT"
