{
  description = "Project formatter module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        formatter = pkgs.writeShellApplication {
          name = "format";
          runtimeInputs = with pkgs; [ nixpkgs-fmt cargo rustfmt ];
          text = ''
            set -euo pipefail

            # Run from the directory nix fmt is invoked in.
            project_root="${PROJECT_ROOT:-$PWD}"
            cd "$project_root"

            echo "Formatting Nix files..."
            nixpkgs-fmt .

            echo "Formatting Rust files..."
            cargo fmt --all
          '';
        };
      }
    );
}

