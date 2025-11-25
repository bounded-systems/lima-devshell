# Build output definition
# This module defines build commands

{ pkgs, projectRoot }:

{
  # Build the project
  default = {
    type = "app";
    program = toString (pkgs.writeShellScript "build" ''
      cd ${projectRoot}
      ${pkgs.cargo}/bin/cargo build --release
    '');
  };
}

