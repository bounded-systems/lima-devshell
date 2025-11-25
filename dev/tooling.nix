# Tooling packages for the development environment
# This file defines what tools are available in the dev shell

{ pkgs }:

with pkgs; [
  # Rust toolchain
  rustc
  cargo
  rustfmt
  clippy
  rust-analyzer
  
  # Build dependencies (matching root flake)
  libgit2
  pkg-config
  
  # Development tools
  git
  just  # Task runner (optional, but useful)
  
  # Linting and formatting
  nixpkgs-fmt  # For formatting flake.nix files
  
  # Testing and debugging
  gdb  # Debugger
]

