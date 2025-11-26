#!/usr/bin/env bash
# Test script to verify all packages and checks build successfully
set -e

echo "=== Testing all packages ==="
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
echo "=== Testing all checks ==="
SYSTEM="${NIX_SYSTEM:-$(nix eval --impure --expr 'builtins.currentSystem' --raw)}"
for check in clippy-check nix-fmt-check rust-fmt-check rust-tests; do
  echo -n "  $check: "
  if nix build --no-warn-dirty ".#checks.$SYSTEM.$check" >/dev/null 2>&1; then
    echo "✓"
  else
    echo "✗ FAILED"
    nix build --no-warn-dirty ".#checks.$SYSTEM.$check" 2>&1 | tail -3
    exit 1
  fi
done

echo ""
echo "=== Testing default build (all) ==="
if nix build --no-warn-dirty >/dev/null 2>&1; then
  echo "  default: ✓"
  echo ""
  echo "=== MANIFEST.json ==="
  if [ -f result/MANIFEST.json ]; then
    ${PYTHON3_BIN}/bin/python3 -m json.tool result/MANIFEST.json 2>/dev/null || cat result/MANIFEST.json
  else
    echo "  MANIFEST.json not found"
  fi
else
  echo "  default: ✗ FAILED"
  nix build --no-warn-dirty 2>&1 | tail -3
  exit 1
fi

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
echo "✓ All builds and checks passed!"

