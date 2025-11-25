{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root is passed from parent flake via follows
    # Parent provides the actual path, so we just declare the input
    project-root.url = "";
  };

  outputs = { self, nixpkgs, flake-utils, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root from input
        projectRoot = toString project-root;
      in
      {
        checks = {
          # Add your checks here
          # Example:
          # flake-check = pkgs.runCommand "flake-check" {} ''
          #   echo "Checking root flake validity..."
          #   ${pkgs.nix}/bin/nix flake check ${projectRoot} --no-build
          #   touch $out
          # '';
        };
      }
    );
}

