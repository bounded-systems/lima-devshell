{
  description = "Development shells module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    config-tooling.url = "path:../config/tooling";
    config-env.url = "path:../config/env";
    
    # Share nixpkgs across config flakes
    config-tooling.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, config-tooling, config-env }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        tooling = config-tooling.packages.${system}.default;
        env = config-env.packages.${system}.default;
        
        # Shell hook (read and display help text, with variable substitution)
        helpText = builtins.readFile ../devshell-help.txt;
        shellHook = ''
          # Display help text with variable substitution
          cat <<EOF
          ${helpText}
          EOF
        '';
      in
      {
        packages.default = pkgs.mkShell {
          # Tooling packages
          buildInputs = tooling;

          # Environment variables (separated from tooling)
          inherit (env) RUST_BACKTRACE RUST_LOG;

          # Shell hook (separated for clarity)
          inherit shellHook;
        };
      }
    );
}

