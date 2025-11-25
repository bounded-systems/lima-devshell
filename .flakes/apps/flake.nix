{
  description = "Launchable programs module - deterministic tool wrappers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, project-root, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # All tools come from nixpkgs input (deterministic)
        cargo = pkgs.cargo;
        findutils = pkgs.findutils;
        # Project root from input
        projectRoot = toString project-root;
      in
      {
        apps = {
          # Pre-Nix preparation: impure operation to prepare inputs for deterministic builds
          # Nix's buildRustPackage uses Cargo.lock + cargoHash to download and verify dependencies
          # No vendoring needed - Nix handles dependency fetching and caching
          impure-flake-prep = {
            type = "app";
            meta = {
              description = "Prepare Rust project for Nix: generate Cargo.lock";
            };
            program = toString (pkgs.writeShellScript "impure-flake-prep" ''
              set -euo pipefail
              # Use current directory (where user runs the command), not store path
              # User should run this from the project root
              
              # Ensure cargo is available (from nixpkgs input)
              export PATH="${cargo}/bin:$PATH"
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  Rust → Nix Preparation"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              
              # Lock dependencies - REQUIRED for Nix
              # Nix's buildRustPackage uses Cargo.lock + cargoHash to:
              # - Download dependencies from crates.io
              # - Verify hashes
              # - Cache in /nix/store
              echo "Locking dependencies..."
              ${cargo}/bin/cargo generate-lockfile
              echo "  ✓ Cargo.lock generated"
              echo ""
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  ✓ Preparation complete"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "Next steps:"
              echo "  1. Commit Cargo.lock for reproducible Nix builds"
              echo "  2. Build with: nix build"
              echo ""
              echo "Note: Nix will download and cache dependencies automatically."
              echo "      No vendoring needed - buildRustPackage handles it."
            '');
          };

          # Update all flake.lock files in root and .flakes/ subdirectories
          update-flakes = {
            type = "app";
            meta = {
              description = "Update flake.lock files for all flakes in root and .flakes/ directories";
            };
            program = toString (pkgs.writeShellScript "update-flakes" ''
              set -euo pipefail
              
              # Use system nix (Determinate Systems) from PATH
              # Ensure find is available
              export PATH="${findutils}/bin:$PATH"
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  Flake Update Tool"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              
              # Collect all flakes first
              declare -a flake_dirs=()
              declare -a flake_names=()
              
              # Add root flake if it exists
              if [ -f "${projectRoot}/flake.nix" ]; then
                flake_dirs+=("${projectRoot}")
                flake_names+=("root")
              fi
              
              # Find all flakes in .flakes/ subdirectories
              if [ -d "${projectRoot}/.flakes" ]; then
                while IFS= read -r flake_file; do
                  flake_dir=$(dirname "$flake_file")
                  flake_name=".flakes/$(basename "$flake_dir")"
                  flake_dirs+=("$flake_dir")
                  flake_names+=("$flake_name")
                done < <(find "${projectRoot}/.flakes" -mindepth 2 -maxdepth 2 -name "flake.nix" -type f 2>/dev/null || true)
              fi
              
              # List all flakes found
              if [ ${#flake_dirs[@]} -eq 0 ]; then
                echo "No flakes found to update."
                exit 0
              fi
              
              echo "Found ${#flake_dirs[@]} flake(s):"
              for i in "''${!flake_names[@]}"; do
                echo "  $((i+1)). ''${flake_names[i]}"
                echo "     ''${flake_dirs[i]}"
              done
              echo ""
              
              # Track success/failure
              updated=0
              failed=0
              failed_dirs=()
              
              # Function to update a flake in a directory
              update_flake() {
                local flake_dir="$1"
                local flake_name="$2"
                
                echo "Updating: $flake_name"
                echo "  Directory: $flake_dir"
                
                if (cd "$flake_dir" && nix flake update); then
                  echo "  ✓ Updated successfully"
                  ((updated++))
                else
                  echo "  ✗ Update failed"
                  ((failed++))
                  failed_dirs+=("$flake_name")
                fi
                echo ""
              }
              
              # Update all collected flakes
              for i in "''${!flake_dirs[@]}"; do
                update_flake "''${flake_dirs[i]}" "''${flake_names[i]}"
              done
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  Summary"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  Updated: $updated"
              echo "  Failed:  $failed"
              
              if [ $failed -gt 0 ]; then
                echo ""
                echo "Failed flakes:"
                for dir in "''${failed_dirs[@]}"; do
                  echo "  - $dir"
                done
                exit 1
              fi
              
              echo ""
              echo "✓ All flakes updated successfully"
            '');
          };
        };
      }
    );
}
