# Test output definition
# This module defines test commands

{ pkgs, projectRoot }:

{
  # Run tests
  default = {
    type = "app";
    program = toString (pkgs.writeShellScript "test" ''
      cd ${projectRoot}
      ${pkgs.cargo}/bin/cargo test
    '');
  };
}

