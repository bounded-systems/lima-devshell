#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

echo "Checking Nix code formatting..."
find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt --check

