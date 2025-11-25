{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Apps flake
    apps-flake.url = "path:./apps";
    
    # Share nixpkgs with apps flake
    # Project root is the parent directory (where Cargo.toml is)
    apps-flake.inputs.nixpkgs.follows = "nixpkgs";
    apps-flake.inputs.project-root.url = "path:..";
  };

  outputs = { self, nixpkgs, flake-utils, apps-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        # Apps output maps directly to apps subflake
        apps = apps-flake.apps.${system};
      }
    );
}
