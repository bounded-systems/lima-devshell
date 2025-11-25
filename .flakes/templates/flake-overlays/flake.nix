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
          # Add your package overrides here
          # Example:
          # myPackage = prev.myPackage.overrideAttrs (oldAttrs: {
          #   # custom overrides
          # });
        };
      };
    };
}

