# This flake owns only the `checks` output space.
# It may depend on: nixpkgs, project-root, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input assets (scripts) are stored in inputs/ directory.
{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Project root path (git repo root) - non-flake path input
    # From .flakes/checks/, need to go up two levels to reach project root
    # Overridden by parent router via follows when used from router
    project-root.url = "path:../..";
    project-root.flake = false;
    # Input scripts directory - non-flake path input
    inputs.url = "path:./inputs";
    inputs.flake = false;
  };

  outputs = { self, nixpkgs, project-root, inputs }:
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
          # Inputs directory path
          inputsDir = toString inputs;
        in
        {
          # Check Nix code formatting
          nix-fmt-check = pkgs.runCommand "nix-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ nixpkgs-fmt findutils ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/nix-fmt-check.sh
            touch $out
          '';

          # Check Rust code formatting
          rust-fmt-check = pkgs.runCommand "rust-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ cargo rustfmt ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/rust-fmt-check.sh
            touch $out
          '';

          # Run clippy check
          clippy-check = pkgs.runCommand "clippy-check"
            {
              nativeBuildInputs = with pkgs; [ cargo clippy ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/clippy-check.sh
            touch $out
          '';

          # Run Rust unit tests
          rust-tests = pkgs.runCommand "rust-tests"
            {
              nativeBuildInputs = with pkgs; [ cargo ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/rust-tests.sh
            touch $out
          '';

          # Graph structure check: validate flake.lock graph and ensure isolation
          # Uses schema validation and checks that all .flakes/* nodes are internal path nodes
          graph-structure-check = pkgs.runCommand "graph-structure-check"
            {
              nativeBuildInputs = with pkgs; [ jq python3 ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/graph-structure-check.sh
            touch $out
          '';

          # Check that all input scripts in .flakes/apps/inputs/ are referenced
          # This ensures no orphaned scripts and helps catch typos
          apps-inputs-usage = pkgs.runCommand "apps-inputs-usage"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/apps-inputs-usage-check.sh
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
            bash ${inputsDir}/no-cross-dir-deps-check.sh
            touch $out
          '';

          # Check shell scripts in all inputs directories
          # Validates syntax, shebangs, and common best practices
          shell-scripts-check = pkgs.runCommand "shell-scripts-check"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
            } ''
            export PROJECT_ROOT="${projectRoot}"
            bash ${inputsDir}/shell-scripts-check.sh
            touch $out
          '';
        });
    };
}
