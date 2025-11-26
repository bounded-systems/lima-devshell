#!/usr/bin/env bash
# Shell hook for the development environment
# Source environment variables from inputs/env.sh
source "${inputsDir}/env.sh"

# Display help text with variable substitution
cat <<EOF
🔧 lima-devshell development environment
Rust: $(rustc --version)
Cargo: $(cargo --version)

Environment:
  RUST_BACKTRACE=$RUST_BACKTRACE
  RUST_LOG=$RUST_LOG

Available commands:
  cargo build          - Build the project
  cargo build --release - Build release binary
  cargo test            - Run tests
  cargo clippy          - Run clippy linter
  cargo fmt             - Format code
  cargo update          - Update dependencies (updates Cargo.lock)

Nix commands:
  nix fmt               - Format all files (Nix, Rust, shell) via formatter flake
  nix flake check       - Run all checks via checks flake
  nix build .#clippy    - Run clippy via packages flake
  nix build .#tests     - Run tests via packages flake

Cargo locking:
  Cargo.lock is managed by cargo in the project root
  Run 'cargo update' to update dependencies and lock file
  Cargo.lock is gitignored - cargo manages it during builds

To test the flake build (from project root):
  nix build

EOF
