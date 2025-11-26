#!/usr/bin/env bash
# Graph-aware flake lock refresh tool with schema validation
# Uses flake.lock schema to validate structure and classify nodes

set -euo pipefail

PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
cd "$PROJECT_ROOT" || {
	echo "Error: Cannot access project root" >&2
	exit 1
}
PROJECT_ROOT=$(pwd)

export PATH="${JQ_BIN}:${NIX_BIN}:$PATH"

GROUP=""
SUBTREE=""
DRY_RUN=false
VALIDATE_ONLY=false

while [ $# -gt 0 ]; do
	case "$1" in
	--group)
		GROUP="$2"
		shift 2
		;;
	--subtree)
		SUBTREE="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--validate-only)
		VALIDATE_ONLY=true
		shift
		;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

FLAKE_LOCK="$PROJECT_ROOT/flake.lock"
POLICY_FILE="$PROJECT_ROOT/.flakes/routes/graph-policy.json"
SCHEMA_FILE="$PROJECT_ROOT/.flakes/routes/flake-lock-schema.json"

if [ ! -f "$FLAKE_LOCK" ]; then
	echo "Error: flake.lock not found"
	exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Flake Graph Refresh Tool"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate flake.lock structure (basic validation using jq)
if [ -f "$FLAKE_LOCK" ] && [ -n "${VALIDATE_SCRIPT:-}" ]; then
	echo "Validating flake.lock structure..."
	bash "$VALIDATE_SCRIPT" "$FLAKE_LOCK" "$SCHEMA_FILE" || {
		echo "  ⚠ Validation failed, continuing anyway..."
	}
fi

if [ "$VALIDATE_ONLY" = "true" ]; then
	exit 0
fi

# Classify nodes
NODES_JSON=$(jq -c '.nodes | to_entries | map({
  name: .key,
  type: .value.locked.type,
  isInternal: (.value.locked.type == "path"),
  isExternal: (.value.locked.type | IN("git", "github", "gitlab", "tarball"))
})' "$FLAKE_LOCK")

# Determine inputs to update
UPDATE_INPUTS=()
if [ -n "$GROUP" ] && [ -f "$POLICY_FILE" ]; then
	GROUP_INPUTS=$(jq -r --arg group "$GROUP" '.groups[$group] // [] | .[]' "$POLICY_FILE")
	for input in $GROUP_INPUTS; do
		UPDATE_INPUTS+=("$input")
	done
else
	# Default: update all external nodes
	for node in $(echo "$NODES_JSON" | jq -r '.[] | select(.isExternal == true) | .name'); do
		UPDATE_INPUTS+=("$node")
	done
fi

if [ ${#UPDATE_INPUTS[@]} -eq 0 ]; then
	echo "No inputs to update"
	exit 0
fi

if [ "$DRY_RUN" = "true" ]; then
	echo "Would update: ''${UPDATE_INPUTS[*]}"
	exit 0
fi

# Update
LOCK_CMD="nix flake lock"
for input in "''${UPDATE_INPUTS[@]}"; do
	LOCK_CMD="$LOCK_CMD --update-input $input"
done
eval "$LOCK_CMD"
