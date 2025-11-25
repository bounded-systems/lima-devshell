{
  description = "Launchable programs module - deterministic tool wrappers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
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
      in
      {
        apps = {
          # Pre-Nix preparation: impure operations to prepare inputs for deterministic builds
          # This command locks dependencies (required) and optionally vendors them
          # Vendoring is optional - Nix only needs Cargo.lock for reproducible builds
          impure-flake-prep = {
            type = "app";
            meta = {
              description = "Prepare Rust project for Nix: lock dependencies (required) and optionally vendor";
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
              
              # (1) Lock dependencies - REQUIRED for Nix
              # Nix needs a stable Cargo.lock to build reproducibly
              echo "[1/2] Locking dependencies..."
              ${cargo}/bin/cargo generate-lockfile
              echo "  ✓ Cargo.lock generated"
              echo ""
              
              # (2) Vendor dependencies - OPTIONAL
              # Vendoring is useful for air-gapped builds or non-Nix reproducibility
              # For Nix itself, Cargo.lock is sufficient
              echo "[2/2] Vendoring dependencies (optional)..."
              if [ ! -f Cargo.lock ]; then
                echo "  ✗ Cargo.lock not found (should not happen)"
                exit 1
              fi
              if ${cargo}/bin/cargo vendor vendor/ 2>/dev/null; then
                echo "  ✓ Dependencies vendored"
                echo "  Note: Vendoring is optional. Nix only requires Cargo.lock."
              else
                echo "  ⊘ Vendoring skipped (cargo vendor not available or failed)"
                echo "  Note: This is fine - Nix only needs Cargo.lock for reproducible builds"
              fi
              echo ""
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  ✓ Preparation complete"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "Next steps:"
              echo "  1. Commit Cargo.lock for reproducible Nix builds"
              echo "  2. (Optional) Commit vendor/ if you need offline/non-Nix builds"
              echo ""
              echo "Note: For Nix builds, Cargo.lock is sufficient. Vendoring is optional."
            '');
          };
        };
      }
    );
}
