{
  description = "Tooling packages configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        packages.default = with pkgs; [
          # Rust toolchain
          rustc
          cargo
          rustfmt
          clippy
          rust-analyzer
          
          # Build dependencies (matching root flake)
          libgit2
          pkg-config
          
          # Development tools
          git
          just  # Task runner (optional, but useful)
          
          # Linting and formatting
          nixpkgs-fmt  # For formatting flake.nix files
          
          # Testing and debugging
          gdb  # Debugger
        ];
      }
    );
}

