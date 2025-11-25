# Checks output definition
# This module defines validation checks

{ pkgs, projectRoot }:

{
  # Check that the root flake is valid
  flake-check = pkgs.runCommand "flake-check" {} ''
    echo "Checking root flake validity..."
    ${pkgs.nix}/bin/nix flake check ${projectRoot} --no-build
    touch $out
  '';

  # Check Rust code formatting
  rust-fmt-check = pkgs.runCommand "rust-fmt-check" {
    nativeBuildInputs = with pkgs; [ cargo rustfmt ];
  } ''
    cd ${projectRoot}
    echo "Checking Rust code formatting..."
    cargo fmt --check --all
    touch $out
  '';

  # Run clippy
  clippy-check = pkgs.runCommand "clippy-check" {
    nativeBuildInputs = with pkgs; [ cargo clippy libgit2 pkg-config ];
  } ''
    cd ${projectRoot}
    echo "Running clippy..."
    cargo clippy --all-targets -- -D warnings
    touch $out
  '';
}

