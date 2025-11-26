#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

echo "Checking flake graph structure..."

FLAKE_LOCK="./flake.lock"
SCHEMA_FILE="./.flakes/routes/flake-lock-schema.json"

if [ ! -f "$FLAKE_LOCK" ]; then
	echo "Warning: flake.lock not found at $FLAKE_LOCK"
	echo "  This check requires the root flake.lock file."
	echo "  Skipping graph structure check."
	exit 0
fi

# Validate against schema if available (using jq-based validation)
if [ -f "$SCHEMA_FILE" ] && [ -f "${VALIDATE_SCRIPT:-}" ]; then
	echo "Validating flake.lock against schema..."
	bash "${VALIDATE_SCRIPT}" "$FLAKE_LOCK" "$SCHEMA_FILE" || {
		echo "  ✗ Schema validation failed"
		exit 1
	}
	echo "  ✓ Schema validation passed"
fi

# Check that all .flakes/* nodes are internal path nodes
VIOLATIONS=0
for node_name in $(jq -r '.nodes | keys[]' "$FLAKE_LOCK" | grep -E '^(apps|checks|packages|devShells|formatter|lib|overlays|templates)-flake$'); do
	NODE_TYPE=$(jq -r --arg name "$node_name" '.nodes[$name].locked.type' "$FLAKE_LOCK")
	NODE_PATH=$(jq -r --arg name "$node_name" '.nodes[$name].locked.path // ""' "$FLAKE_LOCK")

	if [ "$NODE_TYPE" != "path" ]; then
		echo "  ✗ VIOLATION: $node_name is type '$NODE_TYPE', expected 'path'"
		echo "    All .flakes/* subflakes must be internal path nodes"
		VIOLATIONS=$((VIOLATIONS + 1))
	elif [[ ! $NODE_PATH =~ ^\.flakes/ ]]; then
		echo "  ✗ VIOLATION: $node_name path '$NODE_PATH' is not under .flakes/"
		VIOLATIONS=$((VIOLATIONS + 1))
	fi
done

if [ $VIOLATIONS -gt 0 ]; then
	echo ""
	echo "Found $VIOLATIONS violation(s). Graph structure check failed."
	exit 1
fi

echo "  ✓ All .flakes/* nodes are internal path nodes"
echo "  ✓ Graph structure is valid"
