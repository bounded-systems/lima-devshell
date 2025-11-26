# This flake owns only the `checks` output space.
# It may depend on: nixpkgs, crane, project-root, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input assets (scripts) are stored in inputs/ directory.
{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
    # Input scripts directory - non-flake path input
    inputs.url = "path:./inputs";
    inputs.flake = false;
  };

  outputs = { self, nixpkgs, crane, project-root, inputs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      perSystem = f: lib.genAttrs systems f;
    in
    {
      checks = perSystem (system:
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
          # Check Nix code formatting
          nix-fmt-check = pkgs.runCommand "nix-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ nixpkgs-fmt findutils ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputs}/nix-fmt-check.sh
            touch $out
          '';

          # Check Rust code formatting
          rust-fmt-check = pkgs.runCommand "rust-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ cargo rustfmt ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputs}/rust-fmt-check.sh
            touch $out
          '';

          # Run clippy using crane (fetches dependencies from crates.io via Cargo.lock)
          clippy-check = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });

          # Run Rust unit tests
          # Build tests directly using crane (no cross-dir dependency on packages flake)
          rust-tests = craneLib.cargoTest (commonArgs // {
            inherit cargoArtifacts;
          });

          # Graph structure check: validate flake.lock graph and ensure isolation
          # Uses schema validation and checks that all .flakes/* nodes are internal path nodes
          graph-structure-check = pkgs.runCommand "graph-structure-check"
            {
              nativeBuildInputs = with pkgs; [ jq python3 ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputs}/graph-structure-check.sh
            touch $out
          '';

          # Check that all input scripts in .flakes/apps/inputs/ are referenced
          # This ensures no orphaned scripts and helps catch typos
          apps-inputs-usage = pkgs.runCommand "apps-inputs-usage"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputs}/apps-inputs-usage-check.sh
            touch $out
          '';

          # Structural check: detect cross-dir dependency violations
          # This ensures subflakes don't import from other .flakes/* directories
          # Only .flakes/flake.nix (the router) is allowed to import subflakes
          no-cross-dir-deps = pkgs.runCommand "no-cross-dir-deps"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputs}/no-cross-dir-deps-check.sh
            touch $out
          '';
        });
    };
}
