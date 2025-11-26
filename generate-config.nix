# Generate static config file using impure-flakes-prep
# This file generates lima-devshell-config.json from environment variables
# The generated file is gitignored and embedded in the Rust binary at build time

{ pkgs, project-root }:

let
  projectRoot = toString project-root;
  configTemplate = "${projectRoot}/lima-devshell-config.json.template";
in
pkgs.writeTextFile {
  name = "lima-devshell-config.json";
  destination = "/lima-devshell-config.json";
  text = builtins.toJSON {
    bootstrap_flake_path = builtins.getEnv "LIMA_DEVSHELL_BOOTSTRAP_PATH" or "/worktrees/lima-devshell";
    bootstrap_github_url = builtins.getEnv "LIMA_DEVSHELL_BOOTSTRAP_GITHUB" or "github:owner/lima-devshell";
  };
}

