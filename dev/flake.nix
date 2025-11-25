{
  description = "Dev tooling flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Each output concern is its own flake
    devShells.url = "path:./devShells";
    checks.url = "path:./checks";
    apps.url = "path:./apps";
    test.url = "path:./test";
    build.url = "path:./build";
    
    # Share nixpkgs across all subflakes
    devShells.inputs.nixpkgs.follows = "nixpkgs";
    checks.inputs.nixpkgs.follows = "nixpkgs";
    apps.inputs.nixpkgs.follows = "nixpkgs";
    test.inputs.nixpkgs.follows = "nixpkgs";
    build.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, devShells, checks, apps, test, build }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        # Namespaced dev graph
        # This is the structured namespace containing all dev outputs
        dev = {
          # Environment (defaults to dev shell)
          env = {
            default = devShells.packages.${system}.default;
          };

          # Development shells
          devShells = {
            default = devShells.packages.${system}.default;
          };

          # Validation checks
          checks = checks.packages.${system};

          # Convenient run commands
          apps = apps.apps.${system};

          # Test commands
          test = test.apps.${system};

          # Build commands
          build = build.apps.${system};
        };

        # Canonical flake outputs derived from dev.*
        # These re-export the dev namespace as standard flake outputs
        devShells = {
          default = self.dev.devShells.default;
        };
        checks = self.dev.checks;
        apps = self.dev.apps;

        # Formatter for nix files
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
