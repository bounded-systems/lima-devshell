# This flake owns only the `overlays` output space.
# It may depend on: nixpkgs, lib-flake, meta-flake if needed in the future.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Note: Overlays are functions that receive `final` and `prev` from the nixpkgs
# that uses them, so they don't need nixpkgs as an input.
# It must NOT have an inputs/ directory (no assets, only pure overlay functions).
{
  description = "Nixpkgs overlays and overlay utilities";

  outputs = { self }:
    let
      # Helper: Combine multiple overlays into one
      # Usage: combineOverlays [ overlay1 overlay2 overlay3 ]
      combineOverlays = overlays: final: prev:
        let
          # Apply overlays in sequence, each receiving the result of the previous
          applyOverlay = overlay: prevSet: overlay final prevSet;
        in
        builtins.foldl' applyOverlay prev overlays;

      # Helper: Create an overlay that adds a package
      # Usage: addPackage "myPackage" (prev.callPackage ./path { })
      addPackage = name: package: final: prev: {
        ${name} = package;
      };

      # Helper: Create an overlay that overrides a package's attributes
      # Usage: overridePackage "rustc" (old: { version = "1.75.0"; })
      overridePackage = name: overrideFn: final: prev:
        if prev ? ${name}
        then {
          ${name} = prev.${name}.overrideAttrs overrideFn;
        }
        else { };

      # Helper: Create an overlay that replaces a package entirely
      # Usage: replacePackage "cargo" (prev.rustc)
      replacePackage = name: replacement: final: prev: {
        ${name} = replacement;
      };

      # Helper: Create an overlay that adds packages from a set
      # Usage: addPackages { myTool = ...; anotherTool = ...; }
      addPackages = packages: final: prev: packages;
    in
    let
      # Rust toolchain overlay - ensures consistent Rust versions
      # Uncomment and customize as needed
      rustOverlay = final: prev: {
        # Example: Pin to specific Rust version
        # rustc = prev.rustc.overrideAttrs (old: {
        #   version = "1.75.0";
        # });
        # cargo = prev.cargo.overrideAttrs (old: {
        #   version = "1.75.0";
        # });
      };
    in
    {
      overlays = {
        # Default overlay - combines all useful overlays
        # Extend this by adding more overlays to the combineOverlays list
        default = combineOverlays [
          # Add more overlays here as needed
          # rustOverlay
          # customOverlay
        ];

        # Rust toolchain overlay - re-exported for convenience
        rust = rustOverlay;
      };

      # Re-export overlay utilities in lib for convenience
      # These are pure functions, not overlays themselves
      lib = {
        inherit combineOverlays addPackage overridePackage replacePackage addPackages;
        
        # Example usage:
        # combineOverlays = self.overlays.lib.combineOverlays;
        # myOverlay = self.overlays.lib.addPackage "myTool" (prev.callPackage ./path { });
      };
    };
}

