#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

echo "Checking that all .flakes/apps/inputs/*.sh scripts are referenced..."

APPS_FLAKE=".flakes/apps/flake.nix"
INPUTS_DIR=".flakes/apps/inputs"

if [ ! -f "$APPS_FLAKE" ]; then
  echo "Error: $APPS_FLAKE not found"
  exit 1
fi

if [ ! -d "$INPUTS_DIR" ]; then
  echo "Error: $INPUTS_DIR not found"
  exit 1
fi

# Find all .sh files in inputs directory
find "$INPUTS_DIR" -name "*.sh" -type f | while read -r script_file; do
  script_name=$(basename "$script_file")
  echo "Checking if $script_name is referenced..."
  
  # Check if script is referenced in apps/flake.nix
  # Look for the script name in the file (handles both direct paths and env vars)
  if ! grep -q "$script_name" "$APPS_FLAKE"; then
    echo "  ✗ VIOLATION: $script_name is not referenced in $APPS_FLAKE"
    echo "    Unused input scripts should be removed or referenced in the flake"
    exit 1
  fi
done

# Also check for referenced scripts that don't exist
# Extract script references from apps/flake.nix
referenced_scripts=$(grep -oE '[a-zA-Z0-9_-]+\.sh' "$APPS_FLAKE" | sort -u || true)

for script_ref in $referenced_scripts; do
  if [ ! -f "$INPUTS_DIR/$script_ref" ]; then
    echo "  ✗ VIOLATION: $script_ref is referenced in $APPS_FLAKE but not found in $INPUTS_DIR"
    exit 1
  fi
done

echo "✓ All input scripts are properly referenced"

