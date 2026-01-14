#!/bin/bash
#
# Setup a git worktree with symlinks to .vscode and .cursor from the main repo
#
# Usage:
#   .vscode/scripts/setup-worktree.sh <worktree-path> [options]
#
# Options:
#   --prompt "text"     Create .agent-prompt with given text
#   --prompt-file path  Create .agent-prompt from file
#   --open              Open worktree in Cursor after setup
#
# If an .agent-prompt file already exists in the worktree, its contents will be
# copied to clipboard automatically (no flags needed).
#
# Example:
#   .vscode/scripts/setup-worktree.sh ../kserve-RHOAIENG-1234
#   .vscode/scripts/setup-worktree.sh ../kserve-RHOAIENG-1234 --open
#   .vscode/scripts/setup-worktree.sh ../kserve-RHOAIENG-1234 --prompt "Continue work on RHOAIENG-1234"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT=""
PROMPT_FILE_INPUT=""
OPEN_CURSOR=false

# Parse arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <worktree-path> [--prompt \"initial prompt\"] [--prompt-file /path/to/prompt.txt]"
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
        --prompt-file)
            PROMPT_FILE_INPUT="$2"
            shift 2
            ;;
        --open)
            OPEN_CURSOR=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -n "$PROMPT" && -n "$PROMPT_FILE_INPUT" ]]; then
    echo "Error: Use only one of --prompt or --prompt-file"
    exit 1
fi

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

# Handle prompt: from --prompt, --prompt-file, or existing .agent-prompt
PROMPT_FILE="$WORKTREE_PATH/.agent-prompt"
PROMPT_CONTENT=""

if [[ -n "$PROMPT" ]]; then
    echo "$PROMPT" > "$PROMPT_FILE"
    PROMPT_CONTENT="$PROMPT"
    echo "  Created .agent-prompt file (from --prompt)"
elif [[ -n "$PROMPT_FILE_INPUT" ]]; then
    if [[ ! -f "$PROMPT_FILE_INPUT" ]]; then
        echo "Error: Prompt file does not exist: $PROMPT_FILE_INPUT"
        exit 1
    fi
    cat "$PROMPT_FILE_INPUT" > "$PROMPT_FILE"
    PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
    echo "  Created .agent-prompt file (from --prompt-file)"
elif [[ -f "$PROMPT_FILE" ]]; then
    PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
    echo "  Found existing .agent-prompt file"
fi

echo ""
echo "Worktree setup complete!"

# Copy prompt to clipboard if available
if [[ -n "$PROMPT_CONTENT" ]]; then
    if command -v xclip &> /dev/null; then
        echo "$PROMPT_CONTENT" | xclip -selection clipboard
        echo "Prompt copied to clipboard!"
    elif command -v wl-copy &> /dev/null; then
        echo "$PROMPT_CONTENT" | wl-copy
        echo "Prompt copied to clipboard!"
    elif command -v pbcopy &> /dev/null; then
        echo "$PROMPT_CONTENT" | pbcopy
        echo "Prompt copied to clipboard!"
    else
        echo ""
        echo "=== Prompt (copy this) ==="
        echo "$PROMPT_CONTENT"
        echo "==========================="
    fi
fi

echo ""
if [[ "$OPEN_CURSOR" == true ]]; then
    echo "Opening in Cursor..."
    cursor "$WORKTREE_PATH"
else
    echo "To open in Cursor: cursor $WORKTREE_PATH"
fi

