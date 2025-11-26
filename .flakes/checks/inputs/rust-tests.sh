#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

# Check if cargo is available
if ! command -v cargo &> /dev/null; then
  echo "Error: cargo not found in PATH"
  echo "Please ensure Rust toolchain is installed and available"
  exit 1
fi

echo "Running Rust unit tests..."
cargo test --all-targets

