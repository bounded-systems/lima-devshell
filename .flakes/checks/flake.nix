{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, crane, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root from input
        projectRoot = toString project-root;

        # Initialize crane for clippy check - crane.lib.${system} is the craneLib
        craneLib = crane.lib.${system};

        # Filter source files (excludes vendor, target, etc.)
        src = craneLib.cleanCargoSource (craneLib.path projectRoot);

        # Common args for crane builds
        commonArgs = {
          inherit src;
          pname = "lima-devshell";
          version = "0.1.0";
          buildInputs = with pkgs; [
            libgit2
            pkg-config
          ];
        };
      in
      {
        checks = {
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

          # Run clippy using crane (fetches dependencies from crates.io via Cargo.lock)
          clippy-check = craneLib.cargoClippy (commonArgs // {
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });
        };
      }
    );
}
