{
  description = "Development shells module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root is passed from parent flake via follows
    # Parent provides the actual path, so we just declare the input
    project-root.url = "";
  };

  outputs = { self, nixpkgs, flake-utils, project-root }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Tooling packages
        tooling = with pkgs; [
          # Add your development tools here
          # Example:
          # git
          # cargo
          # rustc
        ];

        # Environment variables
        env = {
          # Add your environment variables here
          # Example:
          # RUST_BACKTRACE = "1";
        };

        # Shell hook
        shellHook = ''
          # Add your shell hook here
          # Example:
          # echo "Welcome to the development shell!"
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          # Tooling packages
          buildInputs = tooling;

          # Environment variables
          # inherit (env) RUST_BACKTRACE;

          # Shell hook
          inherit shellHook;
        };
      }
    );
}

