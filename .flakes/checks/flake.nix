{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, crane, project-root }:
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
        # Project root from input
        projectRoot = toString project-root;

        # Initialize crane for clippy check
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
            openssl
            pkg-config
          ];
        };

        # Build cargo artifacts first (dependencies)
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
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
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });

          # Run Rust unit tests
          rust-tests = craneLib.cargoTest (commonArgs // {
            inherit cargoArtifacts;
          });
        };
      }
    );
}
