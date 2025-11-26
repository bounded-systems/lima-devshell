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
    # Inputs directory - static files only (shell hooks, templates, etc.)
    inputs.url = "path:./inputs";
    inputs.flake = false;
  };

  outputs = { self, nixpkgs, inputs }:
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

          # Inputs directory path (relative to flake source)
          inputsDir = "${self}/inputs";

          # Tooling packages
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

          # Environment variables
          env = {
            # Rust development environment
            RUST_BACKTRACE = "1";
            RUST_LOG = "debug";

            # Cargo configuration for proper locking
            # Cargo will manage Cargo.lock in the project root
            # No need to set CARGO_HOME - let cargo use default or system location
          };

          # Shell hook (read from inputs/shell-hook.sh - static file only)
          shellHook = builtins.readFile (inputsDir + "/shell-hook.sh");
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
