# This flake owns only the `checks` output space.
# It may depend on: nixpkgs, crane, project-root, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
{
  description = "Validation checks module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, crane, project-root }:
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
          # Project root from input
          projectRoot = toString project-root;

          # Initialize crane for clippy check
          craneLib = crane.mkLib pkgs;

          # Filter source files (excludes vendor, target, etc.)
          src = craneLib.cleanCargoSource (craneLib.path projectRoot);

          # Common args for crane builds
          commonArgs = {
            inherit src;
            pname = "lima-devshell";
            version = "0.1.0";
            buildInputs = with pkgs; [
              libgit2
              openssl
              pkg-config
            ];
          };

          # Build cargo artifacts first (dependencies)
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          # Check Nix code formatting
          nix-fmt-check = pkgs.runCommand "nix-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ nixpkgs-fmt findutils ];
            } ''
            cd ${projectRoot}
            echo "Checking Nix code formatting..."
            find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt --check
            touch $out
          '';

          # Check Rust code formatting
          rust-fmt-check = pkgs.runCommand "rust-fmt-check"
            {
              nativeBuildInputs = with pkgs; [ cargo rustfmt ];
            } ''
            cd ${projectRoot}
            echo "Checking Rust code formatting..."
            cargo fmt --check --all
            touch $out
          '';

          # Run clippy using crane (fetches dependencies from crates.io via Cargo.lock)
          clippy-check = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });

          # Run Rust unit tests
          # Build tests directly using crane (no cross-dir dependency on packages flake)
          rust-tests = craneLib.cargoTest (commonArgs // {
            inherit cargoArtifacts;
          });

          # Structural check: detect cross-dir dependency violations
          # This ensures subflakes don't import from other .flakes/* directories
          # Only .flakes/flake.nix (the router) is allowed to import subflakes
          no-cross-dir-deps = pkgs.runCommand "no-cross-dir-deps"
            {
              nativeBuildInputs = with pkgs; [ findutils gnugrep ];
            } ''
            cd ${projectRoot}
            echo "Checking for cross-dir dependencies in .flakes/ subflakes..."
            
            violations=0
            flakes_dir=".flakes"
            
            # Find all subflake directories (exclude .flakes/flake.nix itself)
            for flake_dir in "$flakes_dir"/*/; do
              flake_file="$flake_dir/flake.nix"
              if [ ! -f "$flake_file" ]; then
                continue
              fi
              
              flake_name=$(basename "$flake_dir")
              echo "Checking $flake_name..."
              
              # Check for path:../ references to other subflakes
              # This pattern matches: path:../apps, path:../checks, etc.
              if grep -qE 'path:\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file"; then
                echo "  ✗ VIOLATION: $flake_name/flake.nix contains cross-dir dependency"
                echo "    Cross-dir dependencies are forbidden. Only .flakes/flake.nix may import subflakes."
                grep -nE 'path:\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file" || true
                violations=$((violations + 1))
              fi
              
              # Also check for relative imports like ../../apps
              if grep -qE '\.\./\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file"; then
                echo "  ✗ VIOLATION: $flake_name/flake.nix contains relative import to sibling subflake"
                grep -nE '\.\./\.\./(apps|checks|packages|devShells|formatter|lib|overlays|templates)' "$flake_file" || true
                violations=$((violations + 1))
              fi
            done
            
            if [ $violations -gt 0 ]; then
              echo ""
              echo "Found $violations violation(s). Cross-dir dependencies are not allowed."
              echo "Subflakes must be isolated and can only depend on:"
              echo "  - External inputs (nixpkgs, crane, etc.)"
              echo "  - project-root (non-flake path input)"
              echo "  - lib-flake (pure helpers only)"
              echo ""
              echo "All cross-space composition must happen in .flakes/flake.nix (the router)."
              exit 1
            fi
            
            echo "✓ No cross-dir dependencies found"
            touch $out
          '';
        });
    };
}
