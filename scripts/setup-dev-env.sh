#!/bin/bash
#
# Setup development environment for KServe
# - Symlinks .vscode and .cursor from main repo (for worktrees)
# - Creates Python venv and installs dependencies
# - Supports both Poetry (older kserve) and uv (newer kserve with PEP 735)
#
# Usage: .vscode/scripts/setup-dev-env.sh [--force]
#
# Options:
#   --force    Recreate venv even if it exists
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KSERVE_DIR="$PROJECT_ROOT/python/kserve"
VENV_DIR="$KSERVE_DIR/.venv"
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
    local main_repo
    main_repo=$(cd "$gitdir/../.." && pwd)
    if [[ -d "$main_repo/$dir" ]]; then
        echo "Symlinking $dir from main repo: $main_repo"
        ln -s "$main_repo/$dir" "$PROJECT_ROOT/$dir"
    fi
}

# Detect project format
detect_project_format() {
    local pyproject="$KSERVE_DIR/pyproject.toml"
    if [[ ! -f "$pyproject" ]]; then
        echo "none"
        return
    fi
    # Check for PEP 735 dependency-groups (modern uv-compatible format)
    if grep -q '^\[dependency-groups\]' "$pyproject" 2>/dev/null; then
        echo "pep735"
    # Check for Poetry format
    elif grep -q '^\[tool\.poetry\]' "$pyproject" 2>/dev/null; then
        echo "poetry"
    else
        echo "unknown"
    fi
}

ensure_uv() {
    if command -v uv &> /dev/null; then
        return 0
    fi
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # shellcheck disable=SC1090
    source "$HOME/.local/bin/env"
}

ensure_poetry() {
    if command -v poetry &> /dev/null; then
        return 0
    fi
    echo "Installing poetry..."
    curl -sSL https://install.python-poetry.org | python3 -
    export PATH="$HOME/.local/bin:$PATH"
}

install_with_uv() {
    echo "Using: uv $(uv --version)"
    cd "$KSERVE_DIR"
    uv sync --group test --group dev
}

install_with_poetry() {
    echo "Using: $(poetry --version)"
    cd "$KSERVE_DIR"
    poetry config virtualenvs.in-project true --local
    poetry install --with test,dev --extras storage --no-interaction
}

# Setup .vscode and .cursor symlinks for worktrees
setup_worktree_symlinks ".vscode"
setup_worktree_symlinks ".cursor"

# Skip if venv exists (unless --force)
if [[ -d "$VENV_DIR" && "$FORCE" == "false" ]]; then
    echo "Venv already exists at $VENV_DIR"
    echo "Use --force to recreate"
    exit 0
fi

echo "=== KServe Development Environment Setup ==="
echo "Project root: $PROJECT_ROOT"

# Remove existing venv if force
if [[ -d "$VENV_DIR" ]]; then
    echo "Removing existing venv..."
    rm -rf "$VENV_DIR"
fi

# Detect format and install
FORMAT=$(detect_project_format)
echo "Detected pyproject.toml format: $FORMAT"

case "$FORMAT" in
    pep735)
        ensure_uv
        install_with_uv
        ;;
    poetry)
        ensure_poetry
        install_with_poetry
        ;;
    *)
        echo "Error: Could not detect project format from $KSERVE_DIR/pyproject.toml"
        exit 1
        ;;
esac

echo ""
echo "=== Setup Complete ==="
echo "Venv: $VENV_DIR"
echo "Activate with: source $VENV_DIR/bin/activate"
