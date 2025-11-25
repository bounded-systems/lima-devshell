{
  description = "Local development environment for lima-devshell project";

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

        # Import configuration modules
        tooling = import (self + "/config/tooling.nix") { inherit pkgs; };
        env = import (self + "/config/env.nix");

        # Shell hook (read and display help text, with variable substitution)
        helpText = builtins.readFile (self + "/devshell-help.txt");
        shellHook = ''
          # Display help text with variable substitution
          cat <<EOF
          ${helpText}
          EOF
        '';

        # Project root (parent of dev directory)
        # self is the dev/flake.nix path, so we go up one level
        projectRoot = toString (self + "/..");

        # Import output modules
        devShellsModule = import (self + "/modules/devShells.nix") {
          inherit pkgs tooling env shellHook;
        };
        checksModule = import (self + "/modules/checks.nix") {
          inherit pkgs projectRoot;
        };
        appsModule = import (self + "/modules/apps.nix") {
          inherit pkgs projectRoot;
        };
      in
      {
        # Compose outputs from modules
        devShells = devShellsModule;
        checks = checksModule;
        apps = appsModule;

        # Export the devShell as an output that can be referenced
        # This allows the root flake to reference it if needed
        devShell = devShellsModule.default;

        # Formatter for nix files
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
