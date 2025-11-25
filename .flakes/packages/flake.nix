{
  description = "Build artifacts and binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root is passed from parent flake via follows
    project-root.url = "path:../..";
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
          # Build the lima-devshell Rust binary
          lima-devshell = pkgs.rustPlatform.buildRustPackage {
            pname = "lima-devshell";
            version = "0.1.0";
            src = project-root;
            # Use cargoHash - first build will fail with the correct hash to use
            cargoHash = lib.fakeHash;
            buildInputs = with pkgs; [
              libgit2
              pkg-config
            ];
            nativeBuildInputs = with pkgs; [
              pkgs.rustc
              pkg-config
            ];
          };

          # Default package
          default = self.packages.${system}.lima-devshell;
        };
      }
    );
}

