# This flake owns only the `devShells` output space.
# It may depend on: nixpkgs, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input metadata and documentation is stored in inputs/ directory.
{
  description = "Development shells module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      perSystem = f: lib.genAttrs systems f;
    in
    {
      devShells = perSystem (system:
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

          # Shell hook (display help text with variable substitution)
          shellHook = ''
            # Display help text with variable substitution
            cat <<EOF
            🔧 lima-devshell development environment
            Rust: $(rustc --version)
            Cargo: $(cargo --version)

            Environment:
              RUST_BACKTRACE=$RUST_BACKTRACE
              RUST_LOG=$RUST_LOG

            Available commands:
              cargo build          - Build the project
              cargo build --release - Build release binary
              cargo test            - Run tests
              cargo clippy          - Run clippy linter
              cargo fmt             - Format code
              cargo update          - Update dependencies (updates Cargo.lock)

            Nix commands:
              nix fmt               - Format all nix files
              nix flake check       - Check flake validity

            Cargo locking:
              Cargo.lock is managed by cargo in the project root
              Run 'cargo update' to update dependencies and lock file
              Cargo.lock is gitignored - cargo manages it during builds

            To test the flake build (from project root):
              nix build

            EOF
          '';
        in
        {
          default = pkgs.mkShell {
            # Tooling packages
            buildInputs = tooling;

            # Environment variables (separated from tooling)
            inherit (env) RUST_BACKTRACE RUST_LOG;

            # Shell hook (separated for clarity)
            inherit shellHook;
          };
        });
    };
}
