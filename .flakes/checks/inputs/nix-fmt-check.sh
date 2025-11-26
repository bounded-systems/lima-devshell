#!/usr/bin/env bash
set -euo pipefail

# Check formatting of Nix files in the checks flake directory only
# This script should be run from the checks flake directory

echo "Checking Nix code formatting in checks flake..."
find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt --check
