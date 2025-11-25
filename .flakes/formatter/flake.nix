{
  description = "Project formatter module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      forAllSystems = f: lib.genAttrs systems f;
    in
    forAllSystems (system:
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
            if [ -f "Cargo.toml" ]; then
              cargo fmt --all || {
                echo "Warning: cargo fmt failed or made no changes" >&2
                exit 0
              }
              echo "Rust formatting complete"
            else
              echo "No Cargo.toml found, skipping Rust formatting"
            fi
          '';
        };
      }
    );
}

