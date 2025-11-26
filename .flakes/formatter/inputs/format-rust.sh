#!/usr/bin/env bash
set -euo pipefail

# Run from the directory nix fmt is invoked in.
project_root="${PROJECT_ROOT:-$PWD}"
cd "$project_root"

echo "Formatting Rust files..."
if [ -f "Cargo.toml" ]; then
  # Count Rust files
  rust_file_count=$(find . -name "*.rs" -type f | wc -l | tr -d ' ')
  if [ "$rust_file_count" -gt 0 ]; then
    echo "Found $rust_file_count Rust file(s)"
    if command -v cargo &> /dev/null; then
      cargo fmt --all || {
        echo "Warning: cargo fmt failed or made no changes" >&2
        exit 0
      }
      echo "✓ Rust formatting complete"
    else
      echo "Error: cargo not found in PATH"
      echo "  Rust toolchain is required for Rust formatting"
      exit 1
    fi
  else
    echo "No Rust files found, skipping Rust formatting"
  fi
else
  echo "No Cargo.toml found, skipping Rust formatting"
fi

