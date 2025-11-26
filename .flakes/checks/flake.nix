# This flake owns only the `checks` output space.
# It may depend on: nixpkgs, crane, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# This flake is self-contained and only validates its own directory.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Input assets (scripts) are stored in inputs/ directory.
{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    # Input scripts directory - non-flake path input
    inputs.url = "path:./inputs";
    inputs.flake = false;
  };

  outputs = { self, nixpkgs, crane, inputs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      # Import nixpkgs for lib access
      pkgsFor = system: import nixpkgs { inherit system; };
      lib = (pkgsFor "x86_64-linux").lib;
      perSystem = f: lib.genAttrs systems f;
    in
    {
      checks = perSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          # Inputs directory path
          inputsDir = toString inputs;
        in
        {
          # Check Nix code formatting in checks flake only
          nix-fmt-check = pkgs.runCommand "nix-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ nixpkgs-fmt findutils ];
              # Include the checks flake source
              checksSrc = self;
            } ''
            # Copy checks flake to build directory
            cp -r ${self} ./checks-flake
            chmod -R +w ./checks-flake
            cd checks-flake
            bash ${inputsDir}/nix-fmt-check.sh
            touch $out
          '';

          # Check shell scripts in checks/inputs/ directory only
          shell-scripts-check = pkgs.runCommand "shell-scripts-check"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
              # Include the checks flake source
              checksSrc = self;
            } ''
            # Copy checks flake to build directory
            cp -r ${self} ./checks-flake
            chmod -R +w ./checks-flake
            cd checks-flake
            bash ${inputsDir}/shell-scripts-check.sh
            touch $out
          '';

          # Structural check: detect cross-dir dependency violations in checks flake
          # This ensures the checks flake doesn't import from other .flakes/* directories
          no-cross-dir-deps = pkgs.runCommand "no-cross-dir-deps"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
              # Include the checks flake source
              checksSrc = self;
            } ''
            # Copy checks flake to build directory
            cp -r ${self} ./checks-flake
            chmod -R +w ./checks-flake
            cd checks-flake
            bash ${inputsDir}/no-cross-dir-deps-check.sh
            touch $out
          '';
        });
    };
}
