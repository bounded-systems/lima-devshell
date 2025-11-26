# This flake owns only the `overlays` output space.
# It may depend on: nixpkgs, lib-flake, meta-flake if needed in the future.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Note: Overlays are functions that receive `final` and `prev` from the nixpkgs
# that uses them, so they don't need nixpkgs as an input.
# It must NOT have an inputs/ directory (no assets, only pure overlay functions).
{
  description = "Nixpkgs overlays";

  outputs = { self }:
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

