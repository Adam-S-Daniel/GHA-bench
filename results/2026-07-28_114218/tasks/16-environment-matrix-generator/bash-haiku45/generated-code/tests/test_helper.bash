#!/usr/bin/env bash

# Test helper for matrix-generator tests
# Sets up the test environment

export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$PROJECT_ROOT:$PATH"

# Clean up temp files
cleanup() {
    rm -f /tmp/test_config_*.json
}

trap cleanup EXIT
