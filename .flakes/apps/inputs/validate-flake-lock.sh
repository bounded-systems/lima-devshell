#!/usr/bin/env bash
# Validate flake.lock structure using jq (basic validation)
# Checks required fields and basic structure without full JSON Schema validation

set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: validate-flake-lock.sh <lock_file> [schema_file]" >&2
	exit 1
fi

LOCK_FILE="$1"
SCHEMA_FILE="${2:-}"

if [ ! -f "$LOCK_FILE" ]; then
	echo "  ✗ Error: Lock file not found: $LOCK_FILE" >&2
	exit 1
fi

# Basic structural validation using jq
# Check that flake.lock has required top-level fields
if ! jq -e '.version and .nodes' "$LOCK_FILE" >/dev/null 2>&1; then
	echo "  ✗ Validation failed: Missing required fields (version, nodes)"
	exit 1
fi

# Check that version is a number
if ! jq -e '.version | type == "number"' "$LOCK_FILE" >/dev/null 2>&1; then
	echo "  ✗ Validation failed: 'version' must be a number"
	exit 1
fi

# Check that nodes is an object
if ! jq -e '.nodes | type == "object"' "$LOCK_FILE" >/dev/null 2>&1; then
	echo "  ✗ Validation failed: 'nodes' must be an object"
	exit 1
fi

# Check that each node has required fields
NODE_ERRORS=$(jq -r '
  .nodes | to_entries[] | 
  select(.value.locked == null or .value.locked.type == null) |
  "  Missing required fields in node: \(.key)"
' "$LOCK_FILE" 2>/dev/null || true)

if [ -n "$NODE_ERRORS" ]; then
	echo "  ✗ Validation failed: Some nodes are missing required fields:"
	echo "$NODE_ERRORS"
	exit 1
fi

# If schema file provided, we could do more validation, but for now just basic checks
if [ -n "$SCHEMA_FILE" ] && [ -f "$SCHEMA_FILE" ]; then
	# Schema file exists but we're using basic validation only
	# Full JSON Schema validation would require python/jsonschema
	echo "  ⚠ Schema file provided but using basic jq validation only"
	echo "  ⚠ For full JSON Schema validation, use python with jsonschema library"
fi

echo "  ✓ Basic validation passed (structure check)"
exit 0
