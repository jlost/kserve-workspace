#!/bin/bash
# Interactive script to set up required environment variables for KServe workspace
# Verifies and creates variables in ~/.zshenv

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_prompt() {
    # Output to stdout for read -p, but this function should only be used with read -p
    echo -e "${BLUE}[PROMPT]${NC} $1"
}

# Get shell config file
SHELL_CONFIG="$HOME/.zshenv"

# Ensure .zshenv exists
touch "$SHELL_CONFIG"

# Function to check if variable exists in .zshenv
var_exists() {
    local var_name=$1
    grep -q "^export ${var_name}=" "$SHELL_CONFIG" 2>/dev/null
}

# Function to get existing value from .zshenv
get_existing_value() {
    local var_name=$1
    # Get the line, extract value (everything after =), remove comments, strip quotes
    grep "^export ${var_name}=" "$SHELL_CONFIG" 2>/dev/null | \
    cut -d'=' -f2- | \
    sed 's/  #.*$//' | \
    sed 's/^[[:space:]]*//' | \
    sed 's/[[:space:]]*$//' | \
    sed 's/^"//;s/"$//' | \
    sed "s/^'//;s/'$//"
}

# Function to set variable in .zshenv (idempotent - replaces if exists)
set_var() {
    local var_name=$1
    local var_value=$2
    
    # Ensure file exists
    touch "$SHELL_CONFIG"
    
    # Remove ALL existing lines for this variable (including malformed ones)
    # Use grep -v to filter out lines, which is safer than sed with special characters
    local temp_file
    temp_file=$(mktemp)
    
    # Remove lines that start with export VAR_NAME= (with any content after =, including comments)
    # Remove non-export lines starting with variable name
    # Remove any stray lines that are just the value (with or without quotes, with or without comments)
    if [[ -s "$SHELL_CONFIG" ]]; then
        grep -v "^export ${var_name}=" "$SHELL_CONFIG" 2>/dev/null | \
        grep -v "^${var_name}=" | \
        grep -v "^${var_value}$" | \
        grep -v "^${var_value}\"" | \
        grep -v "^${var_value}  #" | \
        grep -v "^${var_value}\"  #" > "$temp_file" || true
    else
        # File is empty, create empty temp file
        touch "$temp_file"
    fi
    
    mv "$temp_file" "$SHELL_CONFIG"
    
    # Add new export (no comments)
    echo "export ${var_name}=${var_value}" >> "$SHELL_CONFIG"
}

# Function to prompt for value with optional default
# Only outputs the value to stdout - all log messages go to stderr
prompt_with_default() {
    local var_name=$1
    local prompt_text=$2
    local default_value=${3:-}
    local is_secret=${4:-false}
    
    local current_value
    if var_exists "$var_name"; then
        current_value=$(get_existing_value "$var_name")
        if [[ -n "$current_value" ]]; then
            if [[ "$is_secret" == "true" ]]; then
                log_info "${var_name} is already set (hidden value)"
            else
                log_info "Current ${var_name}: ${current_value}"
            fi
            # Prompt goes to stderr, read input
            read -p "$(echo -e "${BLUE}[PROMPT]${NC} ${prompt_text} [Press Enter to keep current, or type new value]: ")" input
            if [[ -z "$input" ]]; then
                # Only output value to stdout
                echo "$current_value"
                return
            fi
        fi
    fi
    
    if [[ -n "$default_value" ]]; then
        if [[ "$is_secret" == "true" ]]; then
            read -sp "$(echo -e "${BLUE}[PROMPT]${NC} ${prompt_text} [default: ${default_value}]: ")" input
            echo "" >&2
        else
            read -p "$(echo -e "${BLUE}[PROMPT]${NC} ${prompt_text} [default: ${default_value}]: ")" input
        fi
        # Only output value to stdout
        echo "${input:-$default_value}"
    else
        if [[ "$is_secret" == "true" ]]; then
            read -sp "$(echo -e "${BLUE}[PROMPT]${NC} ${prompt_text}: ")" input
            echo "" >&2
        else
            read -p "$(echo -e "${BLUE}[PROMPT]${NC} ${prompt_text}: ")" input
        fi
        # Only output value to stdout
        echo "${input}"
    fi
}

log_info "=== KServe Workspace Environment Setup ==="
log_info "This script will verify and set required environment variables in ${SHELL_CONFIG}"
echo ""

# QUAY_USERNAME
log_info "--- Quay.io Configuration ---"
quay_username=$(prompt_with_default "QUAY_USERNAME" "Enter your Quay.io username")
if [[ -z "$quay_username" ]]; then
    log_warn "QUAY_USERNAME cannot be empty. Skipping..."
else
    set_var "QUAY_USERNAME" "\"${quay_username}\""
fi

# QUAY_PASSWORD
quay_password=$(prompt_with_default "QUAY_PASSWORD" "Enter your Quay.io password" "" "true")
if [[ -z "$quay_password" ]]; then
    log_warn "QUAY_PASSWORD cannot be empty. Skipping..."
else
    set_var "QUAY_PASSWORD" "\"${quay_password}\""
fi

# QUAY_REPO
quay_repo=$(prompt_with_default "QUAY_REPO" "Enter your Quay.io repository (e.g., quay.io/username/reponame)")
if [[ -z "$quay_repo" ]]; then
    log_warn "QUAY_REPO cannot be empty. Skipping..."
else
    # Trim whitespace
    quay_repo=$(echo "$quay_repo" | xargs)
    set_var "QUAY_REPO" "\"${quay_repo}\""
fi

# KO_DOCKER_REPO (defaults to QUAY_REPO)
if var_exists "QUAY_REPO"; then
    quay_repo_value=$(get_existing_value "QUAY_REPO")
    ko_docker_repo=$(prompt_with_default "KO_DOCKER_REPO" "Enter KO_DOCKER_REPO" "$quay_repo_value")
else
    ko_docker_repo=$(prompt_with_default "KO_DOCKER_REPO" "Enter KO_DOCKER_REPO (usually same as QUAY_REPO)")
fi
if [[ -n "$ko_docker_repo" ]]; then
    set_var "KO_DOCKER_REPO" "\"\${QUAY_REPO}\""
fi

# RUNNING_LOCAL (defaults to true)
running_local=$(prompt_with_default "RUNNING_LOCAL" "Set RUNNING_LOCAL" "true")
set_var "RUNNING_LOCAL" "\"${running_local}\""

# GITHUB_SHA (defaults to master or current git branch)
current_branch="master"
if command -v git &> /dev/null && git rev-parse --git-dir &> /dev/null; then
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")
fi
github_sha=$(prompt_with_default "GITHUB_SHA" "Enter GITHUB_SHA (git branch/commit)" "$current_branch")
set_var "GITHUB_SHA" "\"${github_sha}\""

# ENGINE (defaults to podman)
engine=$(prompt_with_default "ENGINE" "Enter container engine (podman/docker)" "podman")
set_var "ENGINE" "\"${engine}\""

# BUILDER (defaults to ENGINE value)
builder=$(prompt_with_default "BUILDER" "Enter builder" "$engine")
    set_var "BUILDER" "\"\${ENGINE}\""

# HF_TOKEN
log_info "--- HuggingFace Configuration ---"
hf_token=$(prompt_with_default "HF_TOKEN" "Enter your HuggingFace token (hf_...)" "" "true")
if [[ -z "$hf_token" ]]; then
    log_warn "HF_TOKEN is empty. You may need to set this later for private model access."
    set_var "HF_TOKEN" "\"\""
else
    set_var "HF_TOKEN" "\"${hf_token}\""
fi

# BROWSER (defaults to brave-browser)
browser=$(prompt_with_default "BROWSER" "Enter preferred browser" "brave-browser")
    set_var "BROWSER" "\"${browser}\""

echo ""
log_info "=== Setup Complete ==="
log_info "Environment variables have been set in ${SHELL_CONFIG}"
log_info "Please run: source ${SHELL_CONFIG}"
log_info "Or log out and back in for changes to take effect"

