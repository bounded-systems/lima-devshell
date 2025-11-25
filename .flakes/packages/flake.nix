{
  description = "Build artifacts and binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
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

        # Initialize crane using mkLib
        craneLib = crane.mkLib pkgs;

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

        # Build cargo artifacts first (dependencies)
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      in
      {
        packages = {
          # Build the lima-devshell Rust binary using crane
          # Crane automatically fetches dependencies from crates.io using Cargo.lock
          lima-devshell = craneLib.buildPackage commonArgs;

          # Build clippy for offline usage
          # This runs clippy on the codebase and produces a derivation
          # that can be built and cached for offline use
          clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });

          # Default package
          default = self.packages.${system}.lima-devshell;
        };
      }
    );
}

