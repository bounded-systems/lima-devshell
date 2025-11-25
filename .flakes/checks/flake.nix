{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root from input
        projectRoot = toString project-root;
      in
      {
        checks = {
          # Check that the root flake is valid
          flake-check = pkgs.runCommand "flake-check" { } ''
            echo "Checking root flake validity..."
            export NIX_CONFIG="experimental-features = nix-command flakes"
            ${pkgs.nix}/bin/nix flake check ${projectRoot} --no-build
            touch $out
          '';

          # Check Nix code formatting
          nix-fmt-check = pkgs.runCommand "nix-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ nixpkgs-fmt findutils ];
            } ''
            cd ${projectRoot}
            echo "Checking Nix code formatting..."
            find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt --check
            touch $out
          '';

          # Check Rust code formatting
          rust-fmt-check = pkgs.runCommand "rust-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ cargo rustfmt ];
            } ''
            cd ${projectRoot}
            echo "Checking Rust code formatting..."
            cargo fmt --check --all
            touch $out
          '';

          # Run clippy
          clippy-check = pkgs.runCommand "clippy-check"
            {
              nativeBuildInputs = with pkgs; [ cargo clippy libgit2 pkg-config ];
            } ''
            cd ${projectRoot}
            echo "Running clippy..."
            cargo clippy --all-targets -- -D warnings
            touch $out
          '';
        };
      }
    );
}
