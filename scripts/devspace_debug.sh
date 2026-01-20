#!/bin/bash
set -e

COLOR_BLUE="\033[0;94m"
COLOR_GREEN="\033[0;92m"
COLOR_YELLOW="\033[0;93m"
COLOR_RESET="\033[0m"

cd /app/cmd/manager

# Go caches are persisted via devspace persistPaths at /tmp/.cache
# This makes go get fast after first run (modules cached in GOMODCACHE)
echo -e "${COLOR_YELLOW}Running go get...${COLOR_RESET}"
go get
echo -e "${COLOR_GREEN}Dependencies ready${COLOR_RESET}"

# Kill any existing dlv process from a previous session to free port 2345
pkill -9 dlv 2>/dev/null || true
sleep 0.5

echo -e "${COLOR_BLUE}Starting delve debugger on :2345...${COLOR_RESET}"
echo -e "${COLOR_BLUE}Attach your debugger to localhost:2345${COLOR_RESET}"
echo ""

# Run dlv - will rebuild only if source changed (go build cache in GOCACHE)
exec dlv debug --listen=:2345 --headless --accept-multiclient --api-version=2 main.go --
