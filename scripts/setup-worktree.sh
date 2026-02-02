#!/bin/bash
#
# Setup a git worktree for working on a JIRA issue
#
# Usage:
#   setup-worktree.sh --jira RHOAIENG-1234 [options]
#   setup-worktree.sh --prompt="/jira-work RHOAIENG-1234" [options]
#   setup-worktree.sh <worktree-path> [options]  # legacy mode
#
# Options:
#   --jira KEY          JIRA key to work on (auto-creates worktree)
#   --prompt "text"     Prompt text (if contains JIRA key like RHOAIENG-*, auto-creates worktree)
#   --prompt-file path  Read prompt from file
#   --base REMOTE/BRANCH  Override base branch (default: auto-detect from JIRA key)
#   --open              Open worktree in Cursor after setup (default when using --jira)
#   --no-open           Don't open Cursor (override default)
#
# Examples:
#   setup-worktree.sh --jira RHOAIENG-1234
#   setup-worktree.sh --prompt="/jira-work RHOAIENG-1234"
#   setup-worktree.sh --jira RHOAIENG-1234 --base upstream/master
#   setup-worktree.sh ../kserve-RHOAIENG-1234  # legacy: existing worktree
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT=""
PROMPT_FILE_INPUT=""
JIRA_KEY=""
BASE_OVERRIDE=""
OPEN_CURSOR=""  # empty = auto-decide
WORKTREE_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --jira)
            JIRA_KEY="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --prompt-file)
            PROMPT_FILE_INPUT="$2"
            shift 2
            ;;
        --base)
            BASE_OVERRIDE="$2"
            shift 2
            ;;
        --open)
            OPEN_CURSOR="true"
            shift
            ;;
        --no-open)
            OPEN_CURSOR="false"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            # Legacy: positional argument is worktree path
            WORKTREE_PATH="$1"
            shift
            ;;
    esac
done

# Extract JIRA key from prompt if not provided directly
if [[ -z "$JIRA_KEY" && -n "$PROMPT" ]]; then
    # Look for RHOAIENG-NNNN or KSERVE-NNNN pattern
    if [[ "$PROMPT" =~ (RHOAIENG-[0-9]+|KSERVE-[0-9]+) ]]; then
        JIRA_KEY="${BASH_REMATCH[1]}"
        echo "Extracted JIRA key: $JIRA_KEY"
    fi
fi

# If we have a JIRA key but no worktree path, create one
if [[ -n "$JIRA_KEY" && -z "$WORKTREE_PATH" ]]; then
    WORKTREE_PATH="$MAIN_REPO/../kserve-$JIRA_KEY"
    echo "Worktree path: $WORKTREE_PATH"
fi

# Validate we have enough info
if [[ -z "$WORKTREE_PATH" ]]; then
    echo "Usage: $0 --jira RHOAIENG-1234 [options]"
    echo "       $0 --prompt=\"/jira-work RHOAIENG-1234\" [options]"
    echo "       $0 <worktree-path> [options]"
    exit 1
fi

# Check for conflicting prompt sources
if [[ -n "$PROMPT" && -n "$PROMPT_FILE_INPUT" ]]; then
    echo "Error: Use only one of --prompt or --prompt-file"
    exit 1
fi

# Determine base branch
determine_base() {
    local jira="$1"
    if [[ -n "$BASE_OVERRIDE" ]]; then
        echo "$BASE_OVERRIDE"
        return
    fi
    
    # Auto-detect based on JIRA key pattern
    case "$jira" in
        RHOAIENG-*)
            echo "odh/release-0.15"
            ;;
        KSERVE-*)
            echo "upstream/master"
            ;;
        *)
            echo "odh/release-0.15"  # default to ODH
            ;;
    esac
}

# Create worktree if it doesn't exist
if [[ ! -d "$WORKTREE_PATH" ]]; then
    if [[ -z "$JIRA_KEY" ]]; then
        echo "Error: Worktree path does not exist and no JIRA key provided: $WORKTREE_PATH"
        echo "Either provide an existing worktree path or use --jira to create a new one"
        exit 1
    fi
    
    BASE_BRANCH=$(determine_base "$JIRA_KEY")
    echo "Creating worktree for $JIRA_KEY based on $BASE_BRANCH"
    
    # Fetch latest
    cd "$MAIN_REPO"
    REMOTE="${BASE_BRANCH%%/*}"
    echo "Fetching from $REMOTE..."
    git fetch "$REMOTE" --quiet
    
    # Create branch name (JIRA key with suffix for description)
    BRANCH_NAME="${JIRA_KEY}-odh-0.15"
    if [[ "$BASE_BRANCH" == upstream/* ]]; then
        BRANCH_NAME="$JIRA_KEY"
    fi
    
    # Create worktree
    echo "Creating worktree at $WORKTREE_PATH (branch: $BRANCH_NAME)"
    git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" "$BASE_BRANCH"
    
    # Default to opening Cursor for new worktrees
    if [[ -z "$OPEN_CURSOR" ]]; then
        OPEN_CURSOR="true"
    fi
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

# Handle prompt: from --prompt, --prompt-file, --jira, or existing .agent-prompt
PROMPT_FILE="$WORKTREE_PATH/.agent-prompt"
PROMPT_CONTENT=""

if [[ -n "$PROMPT" ]]; then
    PROMPT_CONTENT="$PROMPT"
    echo "$PROMPT_CONTENT" > "$PROMPT_FILE"
    echo "  Created .agent-prompt file (from --prompt)"
elif [[ -n "$PROMPT_FILE_INPUT" ]]; then
    if [[ ! -f "$PROMPT_FILE_INPUT" ]]; then
        echo "Error: Prompt file does not exist: $PROMPT_FILE_INPUT"
        exit 1
    fi
    PROMPT_CONTENT="$(cat "$PROMPT_FILE_INPUT")"
    echo "$PROMPT_CONTENT" > "$PROMPT_FILE"
    echo "  Created .agent-prompt file (from --prompt-file)"
elif [[ -n "$JIRA_KEY" && ! -f "$PROMPT_FILE" ]]; then
    # Auto-generate prompt from JIRA key
    PROMPT_CONTENT="/jira-work $JIRA_KEY"
    echo "$PROMPT_CONTENT" > "$PROMPT_FILE"
    echo "  Created .agent-prompt file (from --jira)"
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
        echo "Prompt copied to clipboard: $PROMPT_CONTENT"
    elif command -v wl-copy &> /dev/null; then
        echo "$PROMPT_CONTENT" | wl-copy
        echo "Prompt copied to clipboard: $PROMPT_CONTENT"
    elif command -v pbcopy &> /dev/null; then
        echo "$PROMPT_CONTENT" | pbcopy
        echo "Prompt copied to clipboard: $PROMPT_CONTENT"
    else
        echo ""
        echo "=== Prompt (copy this) ==="
        echo "$PROMPT_CONTENT"
        echo "==========================="
    fi
fi

echo ""

# Default to not opening if not set
if [[ -z "$OPEN_CURSOR" ]]; then
    OPEN_CURSOR="false"
fi

if [[ "$OPEN_CURSOR" == "true" ]]; then
    echo "Opening in Cursor..."
    cursor "$WORKTREE_PATH"
else
    echo "To open in Cursor: cursor $WORKTREE_PATH"
fi
