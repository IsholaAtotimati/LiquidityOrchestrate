#!/usr/bin/env bash
set -euo pipefail

echo "Running forge build with lint disabled (FORGE_LINT=false)"
FORGE_LINT=false forge build -vvvv "$@"
