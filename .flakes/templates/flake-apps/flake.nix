{
  description = "Launchable programs module - deterministic tool wrappers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Packages flake for building deterministic tools
    packages-flake.url = "path:../packages";
  };

  outputs = { self, nixpkgs, flake-utils, packages-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        apps = {
          # Apps are deterministic wrappers around packages
          # These tools are built deterministically and can be used
          # by the root flake for impure operations (outside sandbox)

          # Example: Wrapper around a package
          # my-tool = {
          #   type = "app";
          #   program = "${packages-flake.packages.${system}.my-tool}/bin/my-tool";
          # };
        };
      }
    );
}

