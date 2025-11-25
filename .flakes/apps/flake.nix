{
  description = "Launchable programs module - deterministic tool wrappers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Packages flake for building deterministic tools
    packages-flake.url = "path:../packages";
    # Project root is passed from parent flake via follows
    # Parent provides the actual path, so we just declare the input
    project-root.url = "";
  };

  outputs = { self, nixpkgs, flake-utils, packages-flake, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # Project root from input
        projectRoot = toString project-root;
        
        # All tools come from nixpkgs input (deterministic)
        cargo = pkgs.cargo;
        # cargo vendor is a built-in subcommand in modern cargo
      in
      {
        apps = {
          # Pre-Nix preparation tools (impure operations)
          # These are deterministic wrappers that run impure operations
          # outside the Nix sandbox to prepare inputs for deterministic builds
          
          # (A) Lock dependencies - Generate/update Cargo.lock
          # Nix never runs cargo update, so we need a stable Cargo.lock
          # before flakes get involved. This makes the dependency graph reproducible.
          lock-deps = {
            type = "app";
            program = toString (pkgs.writeShellScript "lock-deps" ''
              set -euo pipefail
              cd ${projectRoot}
              
              # Ensure cargo is available (from nixpkgs input)
              export PATH="${cargo}/bin:$PATH"
              
              echo "[lock-deps] Generating Cargo.lock..."
              ${cargo}/bin/cargo generate-lockfile
              echo "[lock-deps] ✓ Cargo.lock generated successfully"
              echo "[lock-deps] Commit this file for reproducible Nix builds"
            '');
          };

          # (B) Vendor dependencies - Create vendor/ directory
          # Tools like crate2nix, naersk, crane rely on either:
          # 1. cargo vendor directory (vendor/)
          # 2. crate hashes pinned in the lock file
          # Before Nix enters the picture, ensure every dependency is either
          # vendored or pinned, and no network access is needed.
          vendor-deps = {
            type = "app";
            program = toString (pkgs.writeShellScript "vendor-deps" ''
              set -euo pipefail
              cd ${projectRoot}
              
              # Ensure cargo is available (from nixpkgs input)
              export PATH="${cargo}/bin:$PATH"
              
              # Ensure Cargo.lock exists first
              if [ ! -f Cargo.lock ]; then
                echo "[vendor-deps] Error: Cargo.lock not found"
                echo "[vendor-deps] Run 'nix run .#lock-deps' first"
                exit 1
              fi
              
              echo "[vendor-deps] Creating vendor directory..."
              ${cargo}/bin/cargo vendor vendor/
              echo "[vendor-deps] ✓ Vendor directory created successfully"
              echo "[vendor-deps] Add vendor/ to .gitignore if not committing vendored deps"
            '');
          };

          # Complete Rust pre-Nix preparation
          # Runs all pre-Nix steps in order:
          # (A) Lock dependencies
          # (B) Vendor dependencies
          # (C) Code generation - skipped (no codegen in this project)
          # (D) External tools - handled in flake buildInputs
          # (E) Normalize structure - basic validation
          prep = {
            type = "app";
            program = toString (pkgs.writeShellScript "prep" ''
              set -euo pipefail
              cd ${projectRoot}
              
              # Ensure cargo is available (from nixpkgs input)
              export PATH="${cargo}/bin:$PATH"
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  Rust → Nix Preparation Pipeline"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              
              # (A) Lock dependencies
              echo "[1/4] Locking dependencies..."
              ${cargo}/bin/cargo generate-lockfile
              echo "  ✓ Cargo.lock generated"
              echo ""
              
              # (B) Vendor dependencies
              echo "[2/4] Vendoring dependencies..."
              if [ ! -f Cargo.lock ]; then
                echo "  ✗ Cargo.lock not found (should not happen)"
                exit 1
              fi
              ${cargo}/bin/cargo vendor vendor/ || {
                echo "  ⚠ cargo vendor failed (may need: cargo install cargo-vendor)"
                echo "  Continuing without vendor directory..."
              }
              echo "  ✓ Dependencies vendored (if available)"
              echo ""
              
              # (C) Code generation - skipped for this project
              echo "[3/4] Code generation..."
              echo "  ⊘ Skipped (no codegen that writes to repo)"
              echo ""
              
              # (D) External tools - validation only
              echo "[4/4] Validating project structure..."
              if [ ! -f Cargo.toml ]; then
                echo "  ✗ Cargo.toml not found"
                exit 1
              fi
              if [ ! -f Cargo.lock ]; then
                echo "  ✗ Cargo.lock not found"
                exit 1
              fi
              echo "  ✓ Project structure valid"
              echo ""
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  ✓ Pre-Nix preparation complete"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "Next steps:"
              echo "  1. Commit Cargo.lock for reproducible builds"
              echo "  2. (Optional) Commit vendor/ if using vendored deps"
              echo "  3. Nix can now build deterministically"
            '');
          };
        };
      }
    );
}
