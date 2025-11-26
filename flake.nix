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
    # Re-export outputs from .flakes flake (sub-router)
    # The .flakes/flake.nix router handles all cross-space composition
    {
      lib = flakes.lib or { };
      apps = flakes.apps or { };
      checks = flakes.checks or { };
      formatter = flakes.formatter or { };
      packages = flakes.packages or { };
      devShells = flakes.devShells or { };
    };
}
