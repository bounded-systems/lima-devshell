#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

echo "Checking for cross-dir dependencies in .flakes/ subflakes..."

violations=0
flakes_dir=".flakes"

# Find all subflake directories (exclude .flakes/flake.nix itself)
for flake_dir in "$flakes_dir"/*/; do
	flake_file="$flake_dir/flake.nix"
	if [ ! -f "$flake_file" ]; then
		continue
	fi

	flake_name=$(basename "$flake_dir")
	echo "Checking $flake_name..."

	# Check for path:../ references to other subflakes
	# This pattern matches: path:../apps, path:../checks, etc.
	if grep -qE 'path:\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file"; then
		echo "  ✗ VIOLATION: $flake_name/flake.nix contains cross-dir dependency"
		echo "    Cross-dir dependencies are forbidden. Only .flakes/flake.nix may import subflakes."
		grep -nE 'path:\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file" || true
		violations=$((violations + 1))
	fi

	# Also check for relative imports like ../../apps
	if grep -qE '\.\./\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file"; then
		echo "  ✗ VIOLATION: $flake_name/flake.nix contains relative import to sibling subflake"
		grep -nE '\.\./\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file" || true
		violations=$((violations + 1))
	fi
done

if [ $violations -gt 0 ]; then
	echo ""
	echo "Found $violations violation(s). Cross-dir dependencies are not allowed."
	echo "Subflakes must be isolated and can only depend on:"
	echo "  - External inputs (nixpkgs, crane, etc.)"
	echo "  - project-root (non-flake path input)"
	echo "  - lib-flake (pure helpers only)"
	echo ""
	echo "All cross-space composition must happen in .flakes/flake.nix (the router)."
	exit 1
fi

echo "✓ No cross-dir dependencies found"
