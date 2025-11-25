{
  description = "Local development environment for lima-devshell project";

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

        # Import tooling and environment from separate files
        tooling = import (self + "/tooling.nix") { inherit pkgs; };
        env = import (self + "/env.nix");

        # Shell hook (read and display help text, with variable substitution)
        helpText = builtins.readFile (self + "/devshell-help.txt");
        shellHook = ''
          # Display help text with variable substitution
          cat <<EOF
          ${helpText}
          EOF
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          # Tooling packages
          buildInputs = tooling;

          # Environment variables (separated from tooling)
          inherit (env) RUST_BACKTRACE RUST_LOG;

          # Shell hook (separated for clarity)
          inherit shellHook;
        };

        # Export the devShell as an output that can be referenced
        # This allows the root flake to reference it if needed
        devShell = self.devShells.${system}.default;

        # Formatter for nix files
        formatter = pkgs.nixpkgs-fmt;

        # Project root (parent of dev directory)
        # self is the dev/flake.nix path, so we go up one level
        projectRoot = toString (self + "/..");

        # Checks - validate the flake
        checks = {
          # Check that the root flake is valid
          flake-check = pkgs.runCommand "flake-check" {} ''
            echo "Checking root flake validity..."
            ${pkgs.nix}/bin/nix flake check ${projectRoot} --no-build
            touch $out
          '';

          # Check Rust code formatting
          rust-fmt-check = pkgs.runCommand "rust-fmt-check" {
            nativeBuildInputs = with pkgs; [ cargo rustfmt ];
          } ''
            cd ${projectRoot}
            echo "Checking Rust code formatting..."
            cargo fmt --check --all
            touch $out
          '';

          # Run clippy
          clippy-check = pkgs.runCommand "clippy-check" {
            nativeBuildInputs = with pkgs; [ cargo clippy libgit2 pkg-config ];
          } ''
            cd ${projectRoot}
            echo "Running clippy..."
            cargo clippy --all-targets -- -D warnings
            touch $out
          '';
        };

        # Convenient run commands
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
