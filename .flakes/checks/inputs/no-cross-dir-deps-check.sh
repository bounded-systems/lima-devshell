#!/usr/bin/env bash
set -euo pipefail

# Check that the checks flake doesn't have cross-dir dependencies
# This script should be run from the checks flake directory

echo "Checking for cross-dir dependencies in checks flake..."

FLAKE_FILE="./flake.nix"

if [ ! -f "$FLAKE_FILE" ]; then
  echo "Error: $FLAKE_FILE not found"
  exit 1
fi

violations=0

# Check for path:../ references to other subflakes
# This pattern matches: path:../apps, path:../packages, etc.
if grep -qE 'path:\.\./(apps|packages|devShells|formatter|lib|overlays|templates)' "$FLAKE_FILE"; then
  echo "  ✗ VIOLATION: checks/flake.nix contains cross-dir dependency"
  echo "    Cross-dir dependencies are forbidden. Only .flakes/flake.nix may import subflakes."
  grep -nE 'path:\.\./(apps|packages|devShells|formatter|lib|overlays|templates)' "$FLAKE_FILE" || true
  violations=$((violations + 1))
fi

# Also check for relative imports like ../../apps
if grep -qE '\.\./\.\./(apps|packages|devShells|formatter|lib|overlays|templates)' "$FLAKE_FILE"; then
  echo "  ✗ VIOLATION: checks/flake.nix contains relative import to sibling subflake"
  grep -nE '\.\./\.\./(apps|packages|devShells|formatter|lib|overlays|templates)' "$FLAKE_FILE" || true
  violations=$((violations + 1))
fi

if [ $violations -gt 0 ]; then
  echo ""
  echo "Found $violations violation(s). Cross-dir dependencies are not allowed."
  echo "The checks flake must be isolated and can only depend on:"
  echo "  - External inputs (nixpkgs, crane, etc.)"
  echo "  - inputs/ directory (non-flake path input)"
  echo ""
  echo "All cross-space composition must happen in .flakes/flake.nix (the router)."
  exit 1
fi

echo "✓ No cross-dir dependencies found in checks flake"
