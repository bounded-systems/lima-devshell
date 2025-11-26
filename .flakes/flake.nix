# This is the sub-router flake that composes all subflakes in .flakes/
# It is the ONLY place where cross-space composition is allowed.
# Each subflake (apps, checks, packages, etc.) is isolated and must not
# import from other subflakes. This router imports all subflakes and
# composes their outputs, including cross-space logic like packages + checks.
#
# Routing configuration is defined in .flakes/routes/router-config.json
# This file documents the input sharing structure and can be used for:
# - Documentation and reference
# - Validation and consistency checks
# - Future tooling that generates router code
{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Determinate Systems flake schemas for validation
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/*.tar.gz";

    # Core routing flake - provides routing utilities and reads router-config.json
    routes-core.url = "path:./routes";

    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
    
    # Share nixpkgs and project-root with routes-core
    routes-core.inputs.nixpkgs.follows = "nixpkgs";
    routes-core.inputs.project-root.follows = "project-root";

    # Apps flake
    apps-flake.url = "path:./apps";

    # Share nixpkgs and project-root with apps flake
    apps-flake.inputs.nixpkgs.follows = "nixpkgs";
    apps-flake.inputs.project-root.follows = "project-root";

    # Checks flake
    checks-flake.url = "path:./checks";

    # Share nixpkgs, project-root, and crane with checks flake
    checks-flake.inputs.nixpkgs.follows = "nixpkgs";
    checks-flake.inputs.project-root.follows = "project-root";
    checks-flake.inputs.crane.follows = "crane";

    # Formatter flake
    formatter-flake.url = "path:./formatter";

    # Share nixpkgs with formatter flake
    formatter-flake.inputs.nixpkgs.follows = "nixpkgs";

    # Packages flake
    packages-flake.url = "path:./packages";

    # Share nixpkgs, project-root, and crane with packages flake
    packages-flake.inputs.nixpkgs.follows = "nixpkgs";
    packages-flake.inputs.project-root.follows = "project-root";
    packages-flake.inputs.crane.follows = "crane";

    # Lib flake - pure helper library
    lib-flake.url = "path:./lib";
    
    # Share nixpkgs and flake-utils with lib flake
    lib-flake.inputs.nixpkgs.follows = "nixpkgs";
    lib-flake.inputs.flake-utils.follows = "flake-utils";

    # DevShells flake
    devShells-flake.url = "path:./devShells";

    # Share nixpkgs with devShells flake
    devShells-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, project-root, apps-flake, checks-flake, formatter-flake, packages-flake, lib-flake, devShells-flake, flake-schemas, routes-core, ... }:
    let
      # Use nixpkgs.lib directly instead of importing a specific system's pkgs
      lib = nixpkgs.lib;
      # Use routing utilities from core routing flake
      routeLib = routes-core.lib;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for system-specific packages
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      # Flake schemas for validation (Determinate Systems)
      schemas = flake-schemas.schemas;
      
      # Lib output maps directly to lib subflake (not system-specific)
      lib = lib-flake.lib;
      
      # Expose routing utilities for reference/validation
      routes = routeLib;
      # Apps output: direct re-export (Variant A - subflakes expose apps.${system} directly)
      apps = apps-flake.apps;
      # Checks output: direct re-export (Variant A)
      checks = checks-flake.checks;
      # Formatter output: direct re-export (Variant A)
      formatter = formatter-flake.formatter;
      # DevShells output: direct re-export (Variant A)
      devShells = devShells-flake.devShells;
      # Packages output: composed view that aggregates packages + checks + manifest + all
      # This is the ONLY place where cross-space composition happens
      packages = lib.genAttrs systems (system:
        let
          pkgs = pkgsFor system;
          allPackages = packages-flake.packages.${system};
          allChecks = checks-flake.checks.${system};
          # Helper function to wrap single-file outputs in directories
          # This ensures symlinkJoin can handle both files and directories
          wrapInDir = name: drv:
            pkgs.runCommand "${name}-wrapped"
              {
                inherit drv;
              } ''
              mkdir -p $out
              if [ -f "$drv" ]; then
                # It's a single file, wrap it in a directory with the same name
                cp "$drv" "$out/${name}"
              elif [ -d "$drv" ]; then
                # It's a directory, copy/symlink its contents
                if [ "$(ls -A "$drv" 2>/dev/null)" ]; then
                  # Directory has contents, copy them
                  cp -r "$drv"/* "$out/" 2>/dev/null || true
                else
                  # Empty directory, create a marker
                  touch "$out/.directory"
                fi
              fi
            '';

          # Wrap all packages and checks (single files become directories)
          wrappedPackages = lib.mapAttrs wrapInDir allPackages;
          wrappedChecks = lib.mapAttrs (name: check: wrapInDir "check-${name}" check) allChecks;

          # Create JSON manifest of all packages and checks
          manifestFile = pkgs.writeText "manifest.json" (builtins.toJSON {
            packages = lib.attrNames allPackages;
            checks = lib.attrNames allChecks;
            total_count = (lib.length (lib.attrNames allPackages)) + (lib.length (lib.attrNames allChecks));
          });

          # Wrap manifest file in a directory (symlinkJoin needs directories)
          manifest = pkgs.runCommand "manifest-wrapped"
            {
              inherit manifestFile;
            } ''
            mkdir -p $out
            cp "$manifestFile" "$out/MANIFEST.json"
          '';

          # Create an "all" package that builds everything
          all = pkgs.symlinkJoin {
            name = "all";
            paths = lib.attrValues wrappedPackages ++ lib.attrValues wrappedChecks ++ [ manifest ];
          };
        in
        # Override default to build everything
          # Note: checks are available via .#checks.<name> from the checks output, not packages
        allPackages // {
          default = all;
          all = all; # Named explicitly as well for clarity
        });
      # CI output: explicit CI entrypoint that builds everything + runs all checks
      ci = lib.genAttrs systems (system: {
        all = self.packages.${system}.all or self.packages.${system}.default;
      });
    };
}
