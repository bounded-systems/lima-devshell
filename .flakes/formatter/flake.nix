# This flake owns only the `formatter` output space.
# It may depend on: nixpkgs (for formatting tools).
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input assets (scripts) are stored in inputs/ directory.
{
  description = "Project formatter module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      # Standard systems list (matches lib-flake for consistency)
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      lib = nixpkgs.lib;
      # Helper to apply a function to all systems
      perSystem = f: lib.genAttrs systems f;
      # Format script path (relative to this flake)
      formatScript = ./inputs/format.sh;
    in
    {
      formatter = perSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        pkgs.writeShellApplication {
          name = "format";
          runtimeInputs = with pkgs; [ nixpkgs-fmt cargo rustfmt findutils ];
          # Read script from inputs directory
          text = builtins.readFile formatScript;
        });
    };
}

