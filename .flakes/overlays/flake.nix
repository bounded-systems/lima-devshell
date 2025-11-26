# This flake owns only the `overlays` output space.
# It may depend on: nixpkgs, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input metadata and documentation is stored in inputs/ directory.
{
  description = "Nixpkgs overlays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    {
      overlays = {
        # Default overlay - can be extended with custom package overrides
        default = final: prev: {
          # Example: Override a package if needed
          # somePackage = prev.somePackage.overrideAttrs (oldAttrs: {
          #   # custom overrides
          # });
        };

        # Rust toolchain overlay - ensures consistent Rust versions
        rust = final: prev: {
          # Ensure we use a specific Rust version if needed
          # rustc = prev.rustc;
          # cargo = prev.cargo;
        };
      };
    };
}

