{
  description = "Launchable programs module";

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
        apps = {
          # Format Rust code (nix fmt handles nix files)
          fmt-rust = {
            type = "app";
            program = toString (pkgs.writeShellScript "fmt-rust" ''
              cd ${projectRoot}
              ${pkgs.cargo}/bin/cargo fmt
              echo "Formatted Rust code"
            '');
          };

          # Run tests
          test = {
            type = "app";
            program = toString (pkgs.writeShellScript "test" ''
              cd ${projectRoot}
              ${pkgs.cargo}/bin/cargo test
            '');
          };

          # Build the project
          build = {
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
