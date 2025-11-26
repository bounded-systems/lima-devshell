#!/usr/bin/env bash
# Test script to verify packages build successfully
# Tests only packages from this flake (checks are tested in checks flake)
set -e

echo "=== Testing packages ==="
for pkg in clippy lima-devshell lima-devshell-yaml tests; do
  echo -n "  $pkg: "
  if nix build --no-warn-dirty ".#$pkg" >/dev/null 2>&1; then
    echo "✓"
  else
    echo "✗ FAILED"
    nix build --no-warn-dirty ".#$pkg" 2>&1 | tail -3
    exit 1
  fi
done

echo ""
echo "=== Testing flake check ==="
if nix flake check --no-warn-dirty >/dev/null 2>&1; then
  echo "  flake check: ✓"
else
  echo "  flake check: ✗ FAILED"
  nix flake check --no-warn-dirty 2>&1 | tail -5
  exit 1
fi

echo ""
echo "✓ All package builds passed!"

