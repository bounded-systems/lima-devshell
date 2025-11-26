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
    lib-flake.url = "path:../lib";
    # Inputs directory - static files only (shell hooks, templates, etc.)
    inputs.url = "path:./inputs";
    inputs.flake = false;
  };

  outputs = { self, nixpkgs, lib-flake, inputs }:
    let
      # Use helpers from lib-flake (shared via router)
      systems = lib-flake.lib.systems;
      perSystem = lib-flake.lib.perSystem;
      lib = nixpkgs.lib;
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
