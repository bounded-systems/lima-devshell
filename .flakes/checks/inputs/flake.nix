# Input definitions for checks subflake
{
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  crane.url = "github:ipetkov/crane";
  # Project root path (git repo root) - non-flake path input
  project-root.url = "path:../..";
  project-root.flake = false;
}

