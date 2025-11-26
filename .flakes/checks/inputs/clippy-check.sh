#!/usr/bin/env bash
set -euo pipefail

cd "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

echo "Running clippy..."
cargo clippy --all-targets -- -D warnings

