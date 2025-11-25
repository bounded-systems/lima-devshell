{
  description = "Project formatter module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
          runtimeInputs = with pkgs; [ nixpkgs-fmt cargo rustfmt findutils ];
          text = ''
            set -euo pipefail

            # Run from the directory nix fmt is invoked in.
            project_root="''${PROJECT_ROOT:-''$PWD}"
            cd "$project_root"

            echo "Formatting Nix files..."
            # Format all nix files including .flakes directory
            # nixpkgs-fmt can handle multiple files at once
            find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt

            echo "Formatting Rust files..."
            cargo fmt --all
          '';
        };
      }
    );
}

