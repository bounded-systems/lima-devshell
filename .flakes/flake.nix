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
    packages-flake.url = "path:./packages";
    templates-flake.url = "path:./templates";
    overlays-flake.url = "path:./overlays";
    
    # Share nixpkgs and project-root across all subflakes
    devShells-flake.inputs.nixpkgs.follows = "nixpkgs";
    devShells-flake.inputs.project-root.follows = "project-root";
    checks-flake.inputs.nixpkgs.follows = "nixpkgs";
    checks-flake.inputs.project-root.follows = "project-root";
    apps-flake.inputs.nixpkgs.follows = "nixpkgs";
    apps-flake.inputs.packages-flake.follows = "packages-flake";
    packages-flake.inputs.nixpkgs.follows = "nixpkgs";
    packages-flake.inputs.project-root.follows = "project-root";
  };

  outputs = { self, nixpkgs, flake-utils, devShells-flake, checks-flake, apps-flake, formatter-flake, packages-flake, templates-flake, overlays-flake }:
    let
      # System-specific outputs
      systemOutputs = flake-utils.lib.eachDefaultSystem (system:
        {
          # Canonical flake outputs - each maps directly to a subflake
          devShells = devShells-flake.devShells.${system};
          checks = checks-flake.checks.${system};
          apps = apps-flake.apps.${system};
          formatter = formatter-flake.formatter.${system};
          packages = packages-flake.packages.${system};
        }
      );
    in
      systemOutputs // {
        # Non-system-specific outputs
        templates = templates-flake.templates;
        overlays = overlays-flake.overlays;
      };
}
