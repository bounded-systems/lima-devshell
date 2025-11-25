{
  description = "Build artifacts and binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Project root is passed from parent flake via follows
    # Parent provides the actual path, so we just declare the input
    project-root.url = "";
  };

  outputs = { self, nixpkgs, flake-utils, crane, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root from input
        projectRoot = toString project-root;
        
        # Initialize crane with the project root
        craneLib = crane.mkCraneLib {
          inherit pkgs;
        };
      in
      {
        packages = {
          # Build the lima-devshell Rust binary using crane
          # Crane automatically uses Cargo.lock for deterministic builds
          lima-devshell = craneLib.buildPackage {
            src = project-root;
            pname = "lima-devshell";
            version = "0.1.0";
            buildInputs = with pkgs; [
              libgit2
              pkg-config
            ];
            # Crane handles cargo, rustc, and all build dependencies automatically
          };

          # Default package
          default = self.packages.${system}.lima-devshell;
        };
      }
    );
}

