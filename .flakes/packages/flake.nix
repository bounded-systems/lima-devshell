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
      forAllSystems = f: lib.genAttrs systems f;
    in
    forAllSystems (system:
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
        packages = rec {
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

          # Default package
          default = lima-devshell;
        };
      }
    );
}

