{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Project root (parent of .flakes directory)
    project-root.url = "path:..";
    
    # Each canonical output type is its own flake
    devShells-flake.url = "path:./devShells";
    checks-flake.url = "path:./checks";
    apps-flake.url = "path:./apps";
    formatter-flake.url = "path:./formatter";
    
    # Share nixpkgs and project-root across all subflakes
    devShells-flake.inputs.nixpkgs.follows = "nixpkgs";
    devShells-flake.inputs.project-root.follows = "project-root";
    checks-flake.inputs.nixpkgs.follows = "nixpkgs";
    checks-flake.inputs.project-root.follows = "project-root";
    apps-flake.inputs.nixpkgs.follows = "nixpkgs";
    apps-flake.inputs.project-root.follows = "project-root";
  };

  outputs = { self, nixpkgs, flake-utils, devShells-flake, checks-flake, apps-flake, formatter-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        # Canonical flake outputs - each maps directly to a subflake
        devShells = devShells-flake.devShells.${system};
        checks = checks-flake.checks.${system};
        apps = apps-flake.apps.${system};
        formatter = formatter-flake.formatter.${system};
      }
    );
}
