# Input definitions for apps subflake
# This file defines all inputs used by the apps flake.
# The main flake.nix imports this to keep it clean and focused on outputs.
# Returns an attrset that can be used directly in the inputs attribute.
{
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  # Project root path (git repo root) - non-flake path input
  # Default to parent directory for standalone use, overridden by parent via follows
  project-root.url = "path:../..";
  project-root.flake = false;
}

