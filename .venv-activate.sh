#!/bin/bash
# Auto-activation script for Python virtual environment
# This script can be sourced in your shell: source .venv-activate.sh

if [ -f "${PWD}/python/kserve/.venv/bin/activate" ]; then
    source "${PWD}/python/kserve/.venv/bin/activate"
    echo "✓ Activated Python venv: ${PWD}/python/kserve/.venv"
else
    echo "⚠ Warning: Python venv not found at ${PWD}/python/kserve/.venv"
fi




