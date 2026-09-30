#!/bin/bash
# run-benchmark.sh — Launch the full benchmark on a Sprite (sprites.dev) or any clean VM.
#
# Usage:
#   ./run-benchmark.sh                    # Fresh run, all tasks/models/modes
#   ./run-benchmark.sh --resume <dir>     # Resume a previous run
#
# Prerequisites: python3, claude CLI (with API key configured)
# This script will install: pwsh (PowerShell), actionlint, shellcheck, bats-core

set -eo pipefail
cd "$(dirname "$0")"

echo "=== Benchmark Runner Setup ==="

# Check prerequisites
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "ERROR: claude CLI not found"; exit 1; }

# Check claude CLI works
echo "Testing claude CLI..."
claude -p "say ok" --model claude-sonnet-4-6 --output-format json 2>/dev/null | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
# Output may be a list (stream-json) or dict
if isinstance(data, list):
    result_items = [e for e in data if e.get('type') == 'result']
    assistant_items = [e for e in data if e.get('type') == 'assistant']
    if result_items and result_items[0].get('is_error'):
        print(f'ERROR: claude CLI failed')
        sys.exit(1)
    msg = assistant_items[0]['message']['content'][0]['text'] if assistant_items else 'ok'
    print(f'claude CLI OK: {msg[:50]}')
elif isinstance(data, dict):
    if data.get('is_error'):
        print(f'ERROR: claude CLI failed')
        sys.exit(1)
    print(f'claude CLI OK: {data.get(\"result\",\"\")[:50]}')
" || { echo "ERROR: claude CLI test failed"; exit 1; }

echo ""
echo "=== Installing Runtime Prerequisites ==="

# Install PowerShell if not present
if ! command -v pwsh &>/dev/null; then
    echo "Installing PowerShell..."
    if command -v apt-get &>/dev/null; then
        # Ubuntu/Debian
        sudo apt-get update -qq
        sudo apt-get install -y -qq wget apt-transport-https software-properties-common
        source /etc/os-release
        wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
        sudo dpkg -i packages-microsoft-prod.deb
        rm packages-microsoft-prod.deb
        sudo apt-get update -qq
        sudo apt-get install -y -qq powershell
    else
        echo "WARNING: Cannot auto-install PowerShell on this OS. Install manually."
    fi
fi

if command -v pwsh &>/dev/null; then
    echo "PowerShell: $(pwsh --version)"
    # Install Pester if not present
    pwsh -Command "if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0')) { Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser }" 2>/dev/null
    echo "Pester: $(pwsh -Command '(Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()' 2>/dev/null || echo 'not found')"
else
    echo "WARNING: PowerShell not available — PS modes will fail"
fi

# Install actionlint if not present
if ! command -v actionlint &>/dev/null; then
    echo "Installing actionlint..."
    mkdir -p ~/.local/bin
    curl -sL "https://github.com/rhysd/actionlint/releases/latest/download/actionlint_$(uname -s)_amd64.tar.gz" | tar xz -C ~/.local/bin actionlint
    chmod +x ~/.local/bin/actionlint
    export PATH="$HOME/.local/bin:$PATH"
fi
echo "actionlint: $(actionlint --version 2>&1 | head -1)"

# Install shellcheck if not present
if ! command -v shellcheck &>/dev/null; then
    echo "Installing shellcheck..."
    mkdir -p ~/.local/bin
    curl -sL "https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz" -o /tmp/shellcheck.tar.xz
    tar xf /tmp/shellcheck.tar.xz -C /tmp
    cp /tmp/shellcheck-v0.10.0/shellcheck ~/.local/bin/shellcheck
    chmod +x ~/.local/bin/shellcheck
    rm -rf /tmp/shellcheck.tar.xz /tmp/shellcheck-v0.10.0
    export PATH="$HOME/.local/bin:$PATH"
fi
echo "shellcheck: $(shellcheck --version 2>&1 | grep '^version:' | head -1)"

# Install bats-core if not present
if ! command -v bats &>/dev/null; then
    echo "Installing bats-core..."
    npm install -g bats
fi
echo "bats: $(bats --version)"

# Install act (nektos/act) for running workflows in Docker
if ! command -v act &>/dev/null; then
    echo "Installing act..."
    curl -sL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
fi
echo "act: $(act --version 2>&1)"

# Configure act to use medium-sized runner image, pinned to a dated tag +
# digest (not the floating act-latest, which adopts a new build the day it's
# pushed) per the fleet's 7-day cooling-off policy. To move it, pick a dated
# tag at least 7 days old from https://hub.docker.com/r/catthehacker/ubuntu/tags
# and read its digest from the Docker Hub tags API for that tag.
mkdir -p ~/.config/act
echo '-P ubuntu-latest=catthehacker/ubuntu:act-latest-20260815@sha256:c58e2b364da03b0c804c7d660f2ecbedf2f221a382b9baa0b344b0144780ff43' > ~/.config/act/actrc

# Verify Docker is available (required by act)
if command -v docker &>/dev/null && docker info &>/dev/null; then
    echo "docker: $(docker --version)"
else
    echo "WARNING: Docker not available — workflow execution via act will be skipped"
fi

# Verify bun is present (should be pre-installed)
if command -v bun &>/dev/null; then
    echo "bun: $(bun --version)"
else
    echo "WARNING: bun not available — typescript-bun mode will fail"
fi

echo ""
echo "=== Starting Benchmark (v3 — GHA) ==="
echo "Tasks: 11-18 (GitHub Actions workflow tasks)"
echo "Models: claude-opus-4-6, claude-sonnet-4-6"
echo "Modes: default, powershell, bash, typescript-bun"
echo "Total runs: 64"
echo "Permission mode: --dangerously-skip-permissions"
echo "Hooks: syntax/lint checking enabled on all modes"
echo ""
echo "Results will be pushed to git every 60 seconds."
echo "Expected duration: ~4-8 hours"
echo "Expected cost: ~$24-32"
echo ""

# Run the benchmark
exec python3 runner.py \
    "$@" \
    --tasks 11,12,13,14,15,16,17,18 \
    --models opus,sonnet \
    --modes default,powershell,bash,typescript-bun
