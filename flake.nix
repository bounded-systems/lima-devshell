{
  description = "Bootstrap devshell for Lima VM and Home Manager configuration for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Project root path (git repo root) - non-flake path input
    project-root.url = "path:.";
    project-root.flake = false;

    # .flakes flake - contains all dev tooling
    flakes.url = "path:./.flakes";

    # Share nixpkgs with flakes
    flakes.inputs.nixpkgs.follows = "nixpkgs";
    # Pass project root to flakes (non-flake path, so no circular dependency)
    flakes.inputs.project-root.follows = "project-root";
  };

  outputs = { self, nixpkgs, flakes, project-root, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      forAllSystems = f: lib.genAttrs systems f;
    in
    {
      # Lib output maps directly to .flakes flake (not system-specific)
      lib = flakes.lib or { };
    } // forAllSystems (system:
      {
        # Re-export system-specific outputs from .flakes flake
        apps = flakes.apps.${system} or { };
        checks = flakes.checks.${system} or { };
        formatter = flakes.formatter.${system} or null;
        packages = flakes.packages.${system} or { };
      }
    );
}
