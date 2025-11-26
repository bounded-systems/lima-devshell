{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";

    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;

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

    # Lib flake
    lib-flake.url = "path:./lib";

    # Share nixpkgs with lib flake
    lib-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, project-root, apps-flake, checks-flake, formatter-flake, packages-flake, lib-flake, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      forAllSystems = f: lib.genAttrs systems f;
    in
    {
      # Lib output maps directly to lib subflake (not system-specific)
      lib = lib-flake.lib;
      # Apps output: apps.${system} structure
      # Note: subflakes use forAllSystems which creates ${system}.apps, so we need to access it correctly
      apps = forAllSystems (system: apps-flake.${system}.apps);
      # Checks output: checks.${system} structure
      checks = forAllSystems (system: checks-flake.${system}.checks);
      # Formatter output: formatter.${system} structure
      formatter = forAllSystems (system: formatter-flake.${system}.formatter);
      # Packages output: packages.${system} structure
      # Also include checks as packages so they can be built with nix build .#checks.<name>
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          allPackages = packages-flake.${system}.packages;
          allChecks = checks-flake.${system}.checks;
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
          manifest = pkgs.writeText "manifest.json" (builtins.toJSON {
            packages = lib.attrNames allPackages;
            checks = lib.attrNames allChecks;
            total_count = (lib.length (lib.attrNames allPackages)) + (lib.length (lib.attrNames allChecks));
          });

          # Create an "all" package that builds everything
          all = pkgs.symlinkJoin {
            name = "all";
            paths = lib.attrValues wrappedPackages ++ lib.attrValues wrappedChecks ++ [ manifest ];
            # Rename manifest.json to MANIFEST.json for consistency
            postBuild = ''
              mv $out/manifest.json $out/MANIFEST.json 2>/dev/null || true
            '';
          };
        in
        allPackages // {
          checks = allChecks;
          # Override default to build everything
          default = all;
        });
    };
}
