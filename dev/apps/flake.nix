{
  description = "Convenient run commands module";

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
          # Format all nix files (uses formatter output)
          fmt = {
            type = "app";
            program = toString (pkgs.writeShellScript "fmt" ''
              cd ${projectRoot}
              ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt flake.nix dev/flake.nix
              echo "Formatted nix files"
            '');
          };

          # Format Rust code
          fmt-rust = {
            type = "app";
            program = toString (pkgs.writeShellScript "fmt-rust" ''
              cd ${projectRoot}
              ${pkgs.cargo}/bin/cargo fmt
              echo "Formatted Rust code"
            '');
          };

          # Run all checks
          check = {
            type = "app";
            program = toString (pkgs.writeShellScript "check" ''
              echo "Running flake check..."
              ${pkgs.nix}/bin/nix flake check ${projectRoot} --no-build
              
              echo ""
              echo "Running Rust fmt check..."
              cd ${projectRoot}
              ${pkgs.cargo}/bin/cargo fmt --check --all
              
              echo ""
              echo "Running clippy..."
              ${pkgs.cargo}/bin/cargo clippy --all-targets -- -D warnings
              
              echo ""
              echo "All checks passed!"
            '');
          };
        };
      }
    );
}

