# This flake owns only the `devShells` output space.
# It may depend on: nixpkgs.
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

          # Inputs directory path (relative to flake source)
          inputsDir = "${self}/inputs";

          # Tooling packages
          # Note: Some tools are available via other flakes:
          #   - nixpkgs-fmt: use `nix fmt` (formatter flake)
          #   - clippy/tests: available via `nix build .#clippy` (packages flake)
          tooling = with pkgs; [
            # Rust toolchain (needed for interactive development and IDE support)
            rustc
            cargo
            rustfmt
            clippy
            rust-analyzer

            # Build dependencies (needed to compile the project)
            libgit2
            pkg-config

            # Essential development tools
            git
            direnv # Environment variable management (reads .lima-devshell files)
          ];

          # Shell hook (read from inputs/shell-hook.sh - static file only)
          # Note: Environment variables are sourced from inputs/env.sh within the shell hook
          shellHook = ''
            # Set inputsDir for shell hook to source env.sh
            inputsDir="${inputsDir}"
            ${builtins.readFile (inputsDir + "/shell-hook.sh")}
          '';
        in
        {
          default = pkgs.mkShell {
            # Tooling packages
            buildInputs = tooling;

            # Shell hook (sources env.sh for environment variables)
            inherit shellHook;
          };
        });
    };
}
