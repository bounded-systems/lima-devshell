# This flake owns only the `apps` output space.
# It may depend on: nixpkgs, project-root, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input metadata and documentation is stored in inputs/ directory.
{
  description = "Launchable programs module - deterministic tool wrappers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, project-root, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      perSystem = f: lib.genAttrs systems f;
    in
    {
      apps = perSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          # Project root from input
          projectRoot = toString project-root;
          
          # Tool mapping: tool name -> package
          # This defines which tools are available to scripts via ${TOOL_BIN} env vars
          tools = {
            cargo = pkgs.cargo;
            findutils = pkgs.findutils;
            jq = pkgs.jq;
            nix = pkgs.nix;
          };
          
          # Generate substitution variables from tools mapping
          # Converts { cargo = <pkg>; ... } to { CARGO_BIN = "<pkg>/bin"; ... }
          toolSubstitutions = lib.mapAttrs' 
            (name: pkg: lib.nameValuePair "${lib.toUpper name}_BIN" "${pkg}/bin")
            tools;
          
          # Additional substitutions (non-tool paths)
          extraSubstitutions = {
            # Validation script path (loose contract - script uses VALIDATE_SCRIPT env var)
            VALIDATE_SCRIPT = toString (project-root + "/.flakes/apps/inputs/validate-flake-lock.sh");
          };
          
          # Helper to create app from shell script with automatic tool hydration
          # Automatically substitutes all tools and extra variables into the script
          mkAppFromScript = name: scriptPath: description: {
            type = "app";
            meta = { inherit description; };
            program = toString (pkgs.substituteAll ({
              name = "${name}-script";
              src = scriptPath;
            } // toolSubstitutions // extraSubstitutions));
          };
          
          # Validate that all scripts in inputs/ are referenced
          # This ensures no orphaned scripts and helps catch typos
          _validateInputsUsage = let
            inputsDir = project-root + "/.flakes/apps/inputs";
            # Get all .sh files in inputs directory
            allInputScripts = lib.attrNames (lib.filterAttrs 
              (name: _: lib.hasSuffix ".sh" name)
              (builtins.readDir inputsDir));
            # Scripts that are explicitly referenced in this flake
            referencedScripts = [
              "impure-flake-prep.sh"
              "impure-update-flakes.sh"
              "impure-lock-flakes.sh"
              "graph-refresh.sh"
              "graph-show.sh"
              "validate-flake-lock.sh"  # Referenced via VALIDATE_SCRIPT
            ];
            unused = lib.subtractLists referencedScripts allInputScripts;
            missing = lib.subtractLists allInputScripts referencedScripts;
          in
            if unused != [] then
              throw "Unused input scripts found: ${lib.concatStringsSep ", " unused}. Remove them or add them to referencedScripts."
            else if missing != [] then
              throw "Referenced scripts not found in inputs/: ${lib.concatStringsSep ", " missing}"
            else true;
        in
        {
          # Pre-Nix preparation: impure operation to prepare inputs for deterministic builds
          # Nix's buildRustPackage uses Cargo.lock + cargoHash to download and verify dependencies
          # No vendoring needed - Nix handles dependency fetching and caching
          impure-flake-prep = mkAppFromScript "impure-flake-prep"
            (project-root + "/.flakes/apps/inputs/impure-flake-prep.sh")
            "Prepare Rust project for Nix: generate Cargo.lock";

          # Update all flake.lock files in root and .flakes/ subdirectories
          # Impure operation: modifies flake.lock files in the project directory
          impure-update-flakes = mkAppFromScript "impure-update-flakes"
            (project-root + "/.flakes/apps/inputs/impure-update-flakes.sh")
            "Update flake.lock files for all flakes in root and .flakes/ directories (impure)";

          # Lock all flake.lock files in root and .flakes/ subdirectories
          # Impure operation: creates/updates flake.lock files without updating inputs
          impure-lock-flakes = mkAppFromScript "impure-lock-flakes"
            (project-root + "/.flakes/apps/inputs/impure-lock-flakes.sh")
            "Lock flake.lock files for all flakes in root and .flakes/ directories (impure, no updates)";

          # Graph-aware flake lock refresh tool with schema validation
          # Uses flake.lock schema to validate structure and classify nodes
          graph-refresh = mkAppFromScript "graph-refresh"
            (project-root + "/.flakes/apps/inputs/graph-refresh.sh")
            "Graph-aware flake lock refresh with schema validation";

          # Graph visualization tool
          graph-show = mkAppFromScript "graph-show"
            (project-root + "/.flakes/apps/inputs/graph-show.sh")
            "Show flake input graph (json/mermaid/dot)";
        });
    };
}
