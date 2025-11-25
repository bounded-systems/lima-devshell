{
  description = "Test commands module";

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
          # Run tests
          default = {
            type = "app";
            program = toString (pkgs.writeShellScript "test" ''
              cd ${projectRoot}
              ${pkgs.cargo}/bin/cargo test
            '');
          };
        };
      }
    );
}

