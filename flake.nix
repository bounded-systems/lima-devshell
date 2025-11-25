{
  description = "Bootstrap devshell for Lima VM (just enough to run project nix devshells)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            pkgs = import nixpkgs {
              inherit system;
            };
          in f pkgs
        );
    in {
      devShells = forAllSystems (pkgs: {
        # The only devShell this flake needs
        default = pkgs.mkShell {
          # Minimal set of tools needed to *reach* real devshells
          packages = with pkgs; [
            nix               # Nix CLI inside Lima
            git               # basic git operations if needed
            curl              # fetching things if absolutely necessary
            cacert            # TLS cert bundle
            bashInteractive   # nicer interactive bash
            direnv            # optional but handy, remove if not needed
          ];

          # Keep this very small and focused
          shellHook = ''
            # Enable modern nix features inside this shell
            export NIX_CONFIG="experimental-features = nix-command flakes"

            # Common place for worktrees inside Lima
            export WORKTREES=/worktrees

            # Optional quality-of-life: show where we are
            echo "[lima-devshell] WORKTREES=$WORKTREES"
            echo "[lima-devshell] Nix version: $(nix --version 2>/dev/null || echo 'nix not found')"

            # Optional in-VM worktree guard (belt-and-suspenders check)
            if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
              echo "[lima-devshell] warning: not inside a Git work tree in the VM."
              echo "[lima-devshell] pwd=$(pwd)"
              # Note: We don't exit here since the host-side guard is primary
              # This is just a warning for debugging
            fi
          '';
        };
      });
    };
}

