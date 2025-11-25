{
  description = "Build artifacts and binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root is passed from parent flake via follows
    # Parent provides the actual path, so we just declare the input
    project-root.url = "";
  };

  outputs = { self, nixpkgs, flake-utils, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root from input
        projectRoot = toString project-root;
        lib = nixpkgs.lib;
      in
      {
        packages = {
          # Add your packages here
          # Example for a Rust project:
          # my-binary = pkgs.rustPlatform.buildRustPackage {
          #   pname = "my-binary";
          #   version = "0.1.0";
          #   src = project-root;
          #   cargoHash = lib.fakeHash; # Update after first build
          #   buildInputs = with pkgs; [
          #     # Add build dependencies
          #   ];
          #   nativeBuildInputs = with pkgs; [
          #     # Add native build dependencies
          #   ];
          # };

          # Default package
          # default = self.packages.${system}.my-binary;
        };
      }
    );
}

