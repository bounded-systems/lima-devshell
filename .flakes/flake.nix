{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Project root is passed from parent flake
    # Parent provides project root via path:.
    project-root.url = "";
    
    # Apps flake
    apps-flake.url = "path:./apps";
    
    # Share nixpkgs and project-root with apps flake
    apps-flake.inputs.nixpkgs.follows = "nixpkgs";
    apps-flake.inputs.project-root.follows = "project-root";
  };

  outputs = { self, nixpkgs, flake-utils, project-root, apps-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        # Apps output maps directly to apps subflake
        apps = apps-flake.apps.${system};
      }
    );
}
