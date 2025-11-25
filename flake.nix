{
  description = "Bootstrap devshell for Lima VM and Home Manager configuration for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    
    # .flakes flake - contains all dev tooling
    flakes.url = "path:./.flakes";
    
    # Share nixpkgs with flakes
    flakes.inputs.nixpkgs.follows = "nixpkgs";
    # Pass project root (git repo root) to flakes
    flakes.inputs.project-root.url = "path:.";
  };

  outputs = { self, nixpkgs, flake-utils, flakes }:
    # Delegate all outputs to .flakes flake
    # Project root is passed via PROJECT_ROOT environment variable (git repo root)
    flakes;
}
