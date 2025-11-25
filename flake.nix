{
  description = "Bootstrap devshell for Lima VM and Home Manager configuration for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

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

  outputs = { self, nixpkgs, flake-utils, flakes, project-root, ... }:
    # Re-export only valid outputs from .flakes flake
    # Project root is passed to .flakes via follows (non-flake path input)
    {
      apps = flakes.apps or { };
      checks = flakes.checks or { };
      formatter = flakes.formatter or { };
      packages = flakes.packages or { };
    };
}
