{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
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
    
    # Share nixpkgs and flake-utils with formatter flake
    formatter-flake.inputs.nixpkgs.follows = "nixpkgs";
    formatter-flake.inputs.flake-utils.follows = "flake-utils";
    
    # Packages flake
    packages-flake.url = "path:./packages";
    
    # Share nixpkgs, project-root, and crane with packages flake
    packages-flake.inputs.nixpkgs.follows = "nixpkgs";
    packages-flake.inputs.project-root.follows = "project-root";
    packages-flake.inputs.crane.follows = "crane";
  };

  outputs = { self, nixpkgs, flake-utils, project-root, apps-flake, checks-flake, formatter-flake, packages-flake, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        # Apps output maps directly to apps subflake
        apps = apps-flake.apps.${system};
        # Checks output maps directly to checks subflake
        checks = checks-flake.checks.${system};
        # Formatter output maps directly to formatter subflake
        formatter = formatter-flake.formatter.${system};
        # Packages output maps directly to packages subflake
        packages = packages-flake.packages.${system};
      }
    );
}
