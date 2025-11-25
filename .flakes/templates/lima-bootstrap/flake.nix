{
  description = "A Lima VM bootstrap flake for project devshells";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let pkgs = import nixpkgs { inherit system; };
        in f pkgs);
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nix
            git
            curl
            cacert
            bashInteractive
            direnv
          ];

          shellHook = ''
            export NIX_CONFIG="experimental-features = nix-command flakes"
            export WORKTREES=/worktrees
            echo "[bootstrap] Nix version: $(nix --version)"
            echo "[bootstrap] WORKTREES=$WORKTREES"
          '';
        };
      });
    };
}

