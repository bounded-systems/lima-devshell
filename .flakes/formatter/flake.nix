{
  description = "Project formatter module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root path (git repo root) - non-flake path input
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
        projectRoot = toString project-root;
      in
      {
        formatter = pkgs.writeShellApplication {
          name = "format";
          runtimeInputs = with pkgs; [ nixpkgs-fmt cargo rustfmt ];
          text = ''
            set -euo pipefail
            cd ${projectRoot}
            
            echo "Formatting Nix files..."
            nixpkgs-fmt "$@"
            
            echo "Formatting Rust files..."
            cargo fmt --all
          '';
        };
      }
    );
}

