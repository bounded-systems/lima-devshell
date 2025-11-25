{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
    
    # Apps flake
    apps-flake.url = "path:./apps";
    
    # Share nixpkgs and project-root with apps flake
    apps-flake.inputs.nixpkgs.follows = "nixpkgs";
    apps-flake.inputs.project-root.follows = "project-root";
  };

  outputs = { self, nixpkgs, flake-utils, project-root, apps-flake, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        # Apps output maps directly to apps subflake
        apps = apps-flake.apps.${system};
      }
    );
}
