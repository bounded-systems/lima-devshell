#!/usr/bin/env bash
# Pre-Nix preparation: impure operation to prepare inputs for deterministic builds
# Nix's buildRustPackage uses Cargo.lock + cargoHash to download and verify dependencies
# No vendoring needed - Nix handles dependency fetching and caching

set -euo pipefail
# Use current directory (where user runs the command), not store path
# User should run this from the project root

# Ensure cargo is available (from nixpkgs input)
export PATH="${CARGO_BIN}:$PATH"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Rust → Nix Preparation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Lock dependencies - REQUIRED for Nix
# Nix's buildRustPackage uses Cargo.lock + cargoHash to:
# - Download dependencies from crates.io
# - Verify hashes
# - Cache in /nix/store
echo "Locking dependencies..."
${CARGO_BIN}/cargo generate-lockfile
echo "  ✓ Cargo.lock generated"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Preparation complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Commit Cargo.lock for reproducible Nix builds"
echo "  2. Build with: nix build"
echo ""
echo "Note: Nix will download and cache dependencies automatically."
echo "      No vendoring needed - buildRustPackage handles it."
