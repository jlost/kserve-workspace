#!/bin/bash
#
# Setup development environment for KServe
# - Symlinks .vscode and .cursor from main repo (for worktrees)
# - Creates Python venv and installs test dependencies using uv
#
# Usage: .vscode/scripts/setup-dev-env.sh [--force]
#
# Options:
#   --force    Recreate venv even if it exists
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VENV_DIR="$PROJECT_ROOT/python/kserve/.venv"
FORCE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
    esac
done

# Setup symlinks for worktrees
setup_worktree_symlinks() {
    local dir="$1"
    
    # Skip if directory already exists
    if [[ -e "$PROJECT_ROOT/$dir" ]]; then
        return 0
    fi
    
    # Check if we're in a worktree (`.git` is a file, not a directory)
    if [[ ! -f "$PROJECT_ROOT/.git" ]]; then
        return 0
    fi
    
    # Find the main repo from the worktree's .git file
    # Format: "gitdir: /path/to/main/.git/worktrees/worktree-name"
    local gitdir
    gitdir=$(cat "$PROJECT_ROOT/.git" | sed 's/^gitdir: //')
    # Navigate up from .git/worktrees/name to the main repo
    local main_repo
    main_repo=$(cd "$gitdir/../.." && pwd)
    
    if [[ -d "$main_repo/$dir" ]]; then
        echo "Symlinking $dir from main repo: $main_repo"
        ln -s "$main_repo/$dir" "$PROJECT_ROOT/$dir"
    fi
}

# Setup .vscode and .cursor symlinks for worktrees
setup_worktree_symlinks ".vscode"
setup_worktree_symlinks ".cursor"

# Check for uv
if ! command -v uv &> /dev/null; then
    echo "Error: uv is required but not installed."
    echo "Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Skip if venv exists (unless --force)
if [[ -d "$VENV_DIR" && "$FORCE" == "false" ]]; then
    echo "Venv already exists at $VENV_DIR"
    exit 0
fi

echo "=== KServe Development Environment Setup ==="
echo "Project root: $PROJECT_ROOT"
echo "Using: uv $(uv --version)"

# Remove existing venv if force
if [[ -d "$VENV_DIR" ]]; then
    echo "Removing existing venv..."
    rm -rf "$VENV_DIR"
fi

# Create venv and install dependencies
echo "Creating venv and installing dependencies..."
cd "$PROJECT_ROOT/python/kserve"
uv sync --group test --group dev

echo ""
echo "=== Setup Complete ==="
echo "Venv: $VENV_DIR"
