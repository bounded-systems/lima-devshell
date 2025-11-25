{
  description = "Nixpkgs overlays";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
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

