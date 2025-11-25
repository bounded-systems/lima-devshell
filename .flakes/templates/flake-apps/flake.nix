{
  description = "Launchable programs module";

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
        # Project root from input
        projectRoot = toString project-root;
      in
      {
        apps = {
          # Add your project-specific apps here
          # Note: Use 'nix fmt' for formatting nix files
          # Note: Use 'nix flake check' for flake validation
          # 
          # Example:
          # test = {
          #   type = "app";
          #   program = toString (pkgs.writeShellScript "test" ''
          #     cd ${projectRoot}
          #     ${pkgs.cargo}/bin/cargo test
          #   '');
          # };
        };
      }
    );
}

