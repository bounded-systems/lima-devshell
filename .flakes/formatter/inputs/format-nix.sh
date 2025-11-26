#!/usr/bin/env bash
set -euo pipefail

# Run from the directory nix fmt is invoked in.
project_root="${PROJECT_ROOT:-$PWD}"
cd "$project_root"

echo "Formatting Nix files..."
# Format all nix files including .flakes directory
# nixpkgs-fmt can handle multiple files at once
find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt

echo "✓ Nix formatting complete"

