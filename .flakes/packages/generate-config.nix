# Generate static config file using impure-flakes-prep
# This file generates lima-devshell-config.json from environment variables
# The generated file is gitignored and embedded in the Rust binary at build time

{ pkgs, project-root }:

let
  projectRoot = toString project-root;
in
pkgs.writeTextFile {
  name = "lima-devshell-config.json";
  destination = "/lima-devshell-config.json";
  text = builtins.toJSON {
    bootstrap_flake_path = let env = builtins.getEnv "LIMA_DEVSHELL_BOOTSTRAP_PATH"; in if env != "" then env else "/worktrees/lima-devshell";
    bootstrap_github_url = let env = builtins.getEnv "LIMA_DEVSHELL_BOOTSTRAP_GITHUB"; in if env != "" then env else "github:owner/lima-devshell";
  };
}

