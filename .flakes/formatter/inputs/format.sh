#!/usr/bin/env bash
set -euo pipefail

# Run from the directory nix fmt is invoked in.
project_root="${PROJECT_ROOT:-$PWD}"
cd "$project_root"

echo "Formatting Nix files..."
# Format all nix files including .flakes directory
# nixpkgs-fmt can handle multiple files at once
find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt

echo "Formatting Rust files..."
if [ -f "Cargo.toml" ]; then
  # Count Rust files
  rust_file_count=$(find . -name "*.rs" -type f | wc -l | tr -d ' ')
  if [ "$rust_file_count" -gt 0 ]; then
    echo "Found $rust_file_count Rust file(s)"
    cargo fmt --all || {
      echo "Warning: cargo fmt failed or made no changes" >&2
      exit 0
    }
    echo "Rust formatting complete"
  else
    echo "No Rust files found, skipping Rust formatting"
  fi
else
  echo "No Cargo.toml found, skipping Rust formatting"
fi

