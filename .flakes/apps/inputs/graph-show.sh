#!/usr/bin/env bash
# Graph visualization tool - Show flake input graph (json/mermaid/dot)

set -euo pipefail
FORMAT="''${1:-json}"
FLAKE_LOCK="''${PROJECT_ROOT:-$PWD}/flake.lock"
export PATH="${JQ_BIN}:$PATH"

case "$FORMAT" in
json)
	jq '.nodes | to_entries | map({
      name: .key,
      type: .value.locked.type,
      classification: (if .value.locked.type == "path" then "internal" else "external" end),
      inputs: (.value.inputs // {} | keys)
    })' "$FLAKE_LOCK"
	;;
mermaid)
	echo "graph TD"
	jq -r '.nodes | to_entries[] | (.value.inputs // {} | to_entries[] | "\(.key) --> \(.value)")' "$FLAKE_LOCK"
	;;
*)
	echo "Unknown format: $FORMAT (supported: json, mermaid)"
	exit 1
	;;
esac
