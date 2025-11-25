{
  description = "Development shells module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root is passed from parent flake via follows
    project-root.url = "path:../..";
  };

  outputs = { self, nixpkgs, flake-utils, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Tooling packages (merged from config/tooling)
        tooling = with pkgs; [
          # Rust toolchain
          rustc
          cargo
          rustfmt
          clippy
          rust-analyzer

          # Build dependencies (matching root flake)
          libgit2
          pkg-config

          # Development tools
          git
          just # Task runner (optional, but useful)

          # Linting and formatting
          nixpkgs-fmt # For formatting flake.nix files

          # Testing and debugging
          gdb # Debugger
        ];

        # Environment variables (merged from config/env)
        env = {
          # Rust development environment
          RUST_BACKTRACE = "1";
          RUST_LOG = "debug";

          # Cargo configuration for proper locking
          # Cargo will manage Cargo.lock in the project root
          # No need to set CARGO_HOME - let cargo use default or system location
        };

        # Shell hook (read and display help text, with variable substitution)
        # Read from .flakes directory relative to project root
        helpText = builtins.readFile (project-root + "/.flakes/devshell-help.txt");
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
      }
    );
}
