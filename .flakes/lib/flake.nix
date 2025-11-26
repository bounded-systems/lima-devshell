# This flake owns only the `lib` output space.
# It may depend on: nixpkgs (for lib utilities).
# It must not import from other .flakes/* directories.
# This is a pure helper library with no project-space knowledge.
#
# Inputs are defined in inputs/flake.nix to keep this file focused on outputs.
{
  description = "Pure helper functions and utilities";

  # Import inputs from inputs/flake.nix
  inputs = import ./inputs/flake.nix;

  outputs = { self, nixpkgs, ... }:
    {
      lib = {
        # Example stub function - replace with actual helpers as needed
        # e.g., mkDevShell, mkRustPackage, mkFormatter, etc.
        example = arg: arg;
      };
    };
}

