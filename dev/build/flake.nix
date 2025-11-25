{
  description = "Build commands module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root (parent of dev directory)
        projectRoot = toString (self + "/../..");
      in
      {
        apps = {
          # Build the project
          default = {
            type = "app";
            program = toString (pkgs.writeShellScript "build" ''
              cd ${projectRoot}
              ${pkgs.cargo}/bin/cargo build --release
            '');
          };
        };
      }
    );
}

