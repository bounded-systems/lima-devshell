#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

# Check if cargo is available
if ! command -v cargo &> /dev/null; then
  echo "Error: cargo not found in PATH"
  echo "Please ensure Rust toolchain is installed and available"
  exit 1
fi

# Check if clippy is available
if ! cargo clippy --version &> /dev/null; then
  echo "Error: cargo clippy not found"
  echo "Please install clippy with: rustup component add clippy"
  exit 1
fi

echo "Running clippy..."
cargo clippy --all-targets -- -D warnings

