# devShells output definition
# This module defines the development shell

{ pkgs, tooling, env, shellHook }:

{
  default = pkgs.mkShell {
    # Tooling packages
    buildInputs = tooling;

    # Environment variables (separated from tooling)
    inherit (env) RUST_BACKTRACE RUST_LOG;

    # Shell hook (separated for clarity)
    inherit shellHook;
  };
}

