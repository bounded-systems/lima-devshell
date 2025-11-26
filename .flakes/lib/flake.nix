# This flake owns only the `lib` output space.
# It may depend on: nixpkgs (for lib utilities).
# It must not import from other .flakes/* directories.
# This is a pure helper library with no project-space knowledge.
#
# Input metadata and documentation is stored in inputs/ directory.
{
  description = "Pure helper functions and utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    {
      lib = {
        # Example stub function - replace with actual helpers as needed
        # e.g., mkDevShell, mkRustPackage, mkFormatter, etc.
        example = arg: arg;
      };
    };
}

