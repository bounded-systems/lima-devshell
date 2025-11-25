# Apps output definition
# This module defines convenient run commands

{ pkgs, projectRoot }:

{
  # Format all nix files (uses formatter output)
  fmt = {
    type = "app";
    program = toString (pkgs.writeShellScript "fmt" ''
      cd ${projectRoot}
      ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt flake.nix .flakes/flake.nix
      echo "Formatted nix files"
    '');
  };

  # Format Rust code
  fmt-rust = {
    type = "app";
    program = toString (pkgs.writeShellScript "fmt-rust" ''
      cd ${projectRoot}
      ${pkgs.cargo}/bin/cargo fmt
      echo "Formatted Rust code"
    '');
  };

  # Run all checks
  check = {
    type = "app";
    program = toString (pkgs.writeShellScript "check" ''
      echo "Running flake check..."
      ${pkgs.nix}/bin/nix flake check ${projectRoot} --no-build
      
      echo ""
      echo "Running Rust fmt check..."
      cd ${projectRoot}
      ${pkgs.cargo}/bin/cargo fmt --check --all
      
      echo ""
      echo "Running clippy..."
      ${pkgs.cargo}/bin/cargo clippy --all-targets -- -D warnings
      
      echo ""
      echo "All checks passed!"
    '');
  };

  # Run tests
  test = {
    type = "app";
    program = toString (pkgs.writeShellScript "test" ''
      cd ${projectRoot}
      ${pkgs.cargo}/bin/cargo test
    '');
  };

  # Build the project
  build = {
    type = "app";
    program = toString (pkgs.writeShellScript "build" ''
      cd ${projectRoot}
      ${pkgs.cargo}/bin/cargo build --release
    '');
  };
}

