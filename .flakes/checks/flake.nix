# This flake owns only the `checks` output space.
# It may depend on: nixpkgs, crane, project-root, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
#
# Inputs are defined in inputs/flake.nix to keep this file focused on outputs.
{
  description = "Validation checks module";

  # Import inputs from inputs/flake.nix
  inputs = import ./inputs/flake.nix;

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

          # Graph structure check: validate flake.lock graph and ensure isolation
          # Uses schema validation and checks that all .flakes/* nodes are internal path nodes
          graph-structure-check = pkgs.runCommand "graph-structure-check"
            {
              nativeBuildInputs = with pkgs; [ jq python3 ];
            } ''
            cd ${projectRoot}
            echo "Checking flake graph structure..."
            
            FLAKE_LOCK="./flake.lock"
            SCHEMA_FILE="./.flakes/routes/flake-lock-schema.json"
            
            if [ ! -f "$FLAKE_LOCK" ]; then
              echo "Error: flake.lock not found"
              exit 1
            fi
            
            # Validate against schema if available
            if [ -f "$SCHEMA_FILE" ] && python3 -c "import jsonschema" 2>/dev/null; then
              python3 <<'PYTHON_EOF'
import json
import sys
try:
    import jsonschema
    with open("$SCHEMA_FILE", "r") as f:
        schema = json.load(f)
    with open("$FLAKE_LOCK", "r") as f:
        lock_data = json.load(f)
    jsonschema.validate(instance=lock_data, schema=schema)
    print("  ✓ Schema validation passed")
except ImportError:
    print("  ⚠ jsonschema not available, skipping schema validation")
except jsonschema.ValidationError as e:
    print(f"  ✗ Schema validation failed: {e.message}")
    sys.exit(1)
PYTHON_EOF
            fi
            
            # Check that all .flakes/* nodes are internal path nodes
            VIOLATIONS=0
            for node_name in $(jq -r '.nodes | keys[]' "$FLAKE_LOCK" | grep -E '^(apps|checks|packages|devShells|formatter|lib|overlays|templates)-flake$'); do
              NODE_TYPE=$(jq -r --arg name "$node_name" '.nodes[$name].locked.type' "$FLAKE_LOCK")
              NODE_PATH=$(jq -r --arg name "$node_name" '.nodes[$name].locked.path // ""' "$FLAKE_LOCK")
              
              if [ "$NODE_TYPE" != "path" ]; then
                echo "  ✗ VIOLATION: $node_name is type '$NODE_TYPE', expected 'path'"
                echo "    All .flakes/* subflakes must be internal path nodes"
                VIOLATIONS=$((VIOLATIONS + 1))
              elif [[ ! "$NODE_PATH" =~ ^\.flakes/ ]]; then
                echo "  ✗ VIOLATION: $node_name path '$NODE_PATH' is not under .flakes/"
                VIOLATIONS=$((VIOLATIONS + 1))
              fi
            done
            
            if [ $VIOLATIONS -gt 0 ]; then
              echo ""
              echo "Found $VIOLATIONS violation(s). Graph structure check failed."
              exit 1
            fi
            
            echo "  ✓ All .flakes/* nodes are internal path nodes"
            echo "  ✓ Graph structure is valid"
            touch $out
          '';

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
