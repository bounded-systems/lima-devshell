# This flake owns only the `packages` output space.
# It may depend on: nixpkgs, crane, project-root, lib-flake, meta-flake.
# It must not import from other .flakes/* directories.
# All cross-space composition happens in .flakes/flake.nix (the router).
{
  description = "Build artifacts and binaries";

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
      packages = perSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          # Project root from input
          projectRoot = toString project-root;

          # Initialize crane using mkLib
          craneLib = crane.mkLib pkgs;

          # Filter source files (excludes vendor, target, etc.)
          src = craneLib.cleanCargoSource (craneLib.path projectRoot);

          # Generate static config file using impure-flakes-prep pattern
          # This reads from environment variables at build time and creates a static JSON file
          staticConfig = pkgs.writeTextFile {
            name = "lima-devshell-config.json";
            destination = "/lima-devshell-config.json";
            text = builtins.toJSON {
              bootstrap_flake_path = let env = builtins.getEnv "LIMA_DEVSHELL_BOOTSTRAP_PATH"; in if env != "" then env else "/worktrees/lima-devshell";
              bootstrap_github_url = let env = builtins.getEnv "LIMA_DEVSHELL_BOOTSTRAP_GITHUB"; in if env != "" then env else "github:owner/lima-devshell";
            };
          };

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
            # Embed the static config file in the binary at build time
            # Copy the config file to src/ so it can be included at compile time via include_str!
            # This follows the impure-flakes-prep pattern for static config
            preBuild = ''
              # Copy static config to src/ directory so it can be included at compile time
              cp ${staticConfig}/lima-devshell-config.json src/lima-devshell-config.json
            '';
            # Enable the has-config feature so the config file is included at compile time
            cargoExtraArgs = "--features has-config";
          };

          # Build cargo artifacts first (dependencies)
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        rec {
          # Build the lima-devshell Rust binary using crane
          # Crane automatically fetches dependencies from crates.io using Cargo.lock
          lima-devshell = craneLib.buildPackage commonArgs;

          # Build clippy for offline usage
          # This runs clippy on the codebase and produces a derivation
          # that can be built and cached for offline use
          clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });

          # Build tests for offline usage
          # This runs cargo test on the codebase and produces a derivation
          # that can be built and cached for offline use
          tests = craneLib.cargoTest (commonArgs // {
            inherit cargoArtifacts;
          });

          # Generate lima.yaml template file
          # This is a template YAML file that can be used as a reference
          # The actual YAML is generated dynamically by lima-devshell at runtime
          lima-devshell-yaml = pkgs.writeTextFile {
            name = "lima-devshell-yaml";
            destination = "/lima.yaml";
            text = ''
              # Lima instance for lima-devshell development
              # This is a template - actual values are generated dynamically by lima-devshell
              vmType: vz
              arch: aarch64
              images:
              - location: https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img
                arch: aarch64
              mounts:
              - location: /Users/USER/.local/state/git/worktrees/REPO/WORKTREE
                mountPoint: /worktrees/REPO/WORKTREE
                writable: true
              - location: /Users/USER/.local/share/git/bare/REPO.git/worktrees
                mountPoint: /git/bare/worktrees
                writable: true
              memory: 6GiB
              cpus: 4
              disk: 80GiB
              ssh:
                localPort: 0
                loadDotSSHPubKeys: true
              env:
                LIMA_WORKDIR_DISABLED: '1'
              provision:
              - mode: system
                script: |
                  #!/bin/sh
                  # Create user if not present
                  if ! id dev >/dev/null 2>&1; then
                    useradd -m -s /bin/bash dev
                    passwd -d dev
                    usermod -aG sudo dev
                  fi
            '';
          };

          # Test script to verify all packages and checks build successfully
          test-all-builds = pkgs.writeShellApplication {
            name = "test-all-builds";
            text = ''
              set -e
              
              echo "=== Testing all packages ==="
              for pkg in clippy lima-devshell lima-devshell-yaml tests; do
                echo -n "  $pkg: "
                if nix build --no-warn-dirty ".#$pkg" >/dev/null 2>&1; then
                  echo "✓"
                else
                  echo "✗ FAILED"
                  nix build --no-warn-dirty ".#$pkg" 2>&1 | tail -3
                  exit 1
                fi
              done
              
              echo ""
              echo "=== Testing all checks ==="
              SYSTEM="''${NIX_SYSTEM:-$(nix eval --impure --expr 'builtins.currentSystem' --raw)}"
              for check in clippy-check nix-fmt-check rust-fmt-check rust-tests; do
                echo -n "  $check: "
                if nix build --no-warn-dirty ".#checks.$SYSTEM.$check" >/dev/null 2>&1; then
                  echo "✓"
                else
                  echo "✗ FAILED"
                  nix build --no-warn-dirty ".#checks.$SYSTEM.$check" 2>&1 | tail -3
                  exit 1
                fi
              done
              
              echo ""
              echo "=== Testing default build (all) ==="
              if nix build --no-warn-dirty >/dev/null 2>&1; then
                echo "  default: ✓"
                echo ""
                echo "=== MANIFEST.json ==="
                if [ -f result/MANIFEST.json ]; then
                  ${pkgs.python3}/bin/python3 -m json.tool result/MANIFEST.json 2>/dev/null || cat result/MANIFEST.json
                else
                  echo "  MANIFEST.json not found"
                fi
              else
                echo "  default: ✗ FAILED"
                nix build --no-warn-dirty 2>&1 | tail -3
                exit 1
              fi
              
              echo ""
              echo "=== Testing flake check ==="
              if nix flake check --no-warn-dirty >/dev/null 2>&1; then
                echo "  flake check: ✓"
              else
                echo "  flake check: ✗ FAILED"
                nix flake check --no-warn-dirty 2>&1 | tail -5
                exit 1
              fi
              
              echo ""
              echo "✓ All builds and checks passed!"
            '';
          };

          # Default package
          default = lima-devshell;
        });
    };
}

