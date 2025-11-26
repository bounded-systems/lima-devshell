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
          
          # Inputs directory path (relative to project root)
          # project-root points to .flakes/ (from path:..), so we need apps/inputs
          inputsDir = project-root + "/apps/inputs";
          
          # Helper to get script path from filename
          scriptPath = scriptName: inputsDir + "/${scriptName}";
          
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
            VALIDATE_SCRIPT = toString (scriptPath "validate-flake-lock.sh");
          };
          
          # Helper to create app from shell script with automatic tool hydration
          # Automatically substitutes all tools and extra variables into the script
          # Reads script content and replaces ${VAR} patterns with actual values
          mkAppFromScript = name: scriptPath: description: let
            allVars = toolSubstitutions // extraSubstitutions;
            # Read script and replace all ${VAR} patterns
            scriptContent = builtins.readFile scriptPath;
            # Replace each variable: ${VAR} -> value
            replacedContent = lib.foldl' (content: varName:
              let varValue = allVars.${varName}; in
              lib.replaceStrings ["${" + varName + "}"] [varValue] content
            ) scriptContent (lib.attrNames allVars);
          in {
            type = "app";
            meta = { inherit description; };
            program = toString (pkgs.writeShellScript "${name}-script" replacedContent);
          };
          
          # Define all apps with their script filenames (not full paths)
          # Script paths are constructed dynamically from inputsDir
          appDefinitions = {
            "impure-flake-prep" = {
              script = "impure-flake-prep.sh";
              description = "Prepare Rust project for Nix: generate Cargo.lock";
            };
            "impure-update-flakes" = {
              script = "impure-update-flakes.sh";
              description = "Update flake.lock files for all flakes in root and .flakes/ directories (impure)";
            };
            "impure-lock-flakes" = {
              script = "impure-lock-flakes.sh";
              description = "Lock flake.lock files for all flakes in root and .flakes/ directories (impure, no updates)";
            };
            "graph-refresh" = {
              script = "graph-refresh.sh";
              description = "Graph-aware flake lock refresh with schema validation";
            };
            "graph-show" = {
              script = "graph-show.sh";
              description = "Show flake input graph (json/mermaid/dot)";
            };
          };
        in
        # Build apps from definitions using dynamic paths
        lib.mapAttrs
          (name: def: mkAppFromScript name (scriptPath def.script) def.description)
          appDefinitions
      );
    };
}
