#!/bin/bash
#
# Setup a git worktree with symlinks to .vscode and .cursor from the main repo
#
# Usage: .vscode/scripts/setup-worktree.sh <worktree-path> [--prompt "initial prompt"]
#
# Example:
#   .vscode/scripts/setup-worktree.sh ../kserve-RHOAIENG-1234
#   .vscode/scripts/setup-worktree.sh ../kserve-RHOAIENG-1234 --prompt "Continue work on RHOAIENG-1234"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT=""

# Parse arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <worktree-path> [--prompt \"initial prompt\"]"
    echo "Example: $0 ../kserve-RHOAIENG-1234"
    exit 1
fi

WORKTREE_PATH="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree path does not exist: $WORKTREE_PATH"
    exit 1
fi

WORKTREE_PATH="$(cd "$WORKTREE_PATH" && pwd)"

echo "Setting up worktree: $WORKTREE_PATH"
echo "Main repo: $MAIN_REPO"

# Create symlinks for .vscode and .cursor
for dir in .vscode .cursor; do
    if [[ -e "$WORKTREE_PATH/$dir" ]]; then
        echo "  $dir already exists, skipping"
    elif [[ -d "$MAIN_REPO/$dir" ]]; then
        echo "  Symlinking $dir"
        ln -s "$MAIN_REPO/$dir" "$WORKTREE_PATH/$dir"
    else
        echo "  $dir not found in main repo, skipping"
    fi
done

# Write prompt file if provided
PROMPT_FILE="$WORKTREE_PATH/.agent-prompt"
if [[ -n "$PROMPT" ]]; then
    echo "$PROMPT" > "$PROMPT_FILE"
    echo "  Created .agent-prompt file"
fi

echo ""
echo "Worktree setup complete!"

# Copy prompt to clipboard if available and prompt was provided
if [[ -n "$PROMPT" ]]; then
    if command -v xclip &> /dev/null; then
        echo "$PROMPT" | xclip -selection clipboard
        echo "Prompt copied to clipboard!"
    elif command -v wl-copy &> /dev/null; then
        echo "$PROMPT" | wl-copy
        echo "Prompt copied to clipboard!"
    elif command -v pbcopy &> /dev/null; then
        echo "$PROMPT" | pbcopy
        echo "Prompt copied to clipboard!"
    else
        echo ""
        echo "=== Prompt (copy this) ==="
        echo "$PROMPT"
        echo "==========================="
    fi
fi

echo ""
echo "To open in Cursor: cursor $WORKTREE_PATH"

