# Templates flake has no inputs - it only provides template outputs.
# Inputs are defined in inputs/flake.nix (empty) to maintain consistency.
{
  description = "Project templates for bootstrapping";

  # Import inputs from inputs/flake.nix (empty for templates)
  inputs = import ./inputs/flake.nix;

  outputs = { self }:
    {
      templates = {
        # Basic Rust project template with flake structure
        rust-project = {
          path = ./rust-project;
          description = "A basic Rust project with Nix flake support";
        };

        # Lima devshell bootstrap template
        lima-bootstrap = {
          path = ./lima-bootstrap;
          description = "A Lima VM bootstrap flake for project devshells";
        };

        # Individual flake output templates
        flake-apps = {
          path = ./flake-apps;
          description = "Template for apps flake output";
        };

        flake-checks = {
          path = ./flake-checks;
          description = "Template for checks flake output";
        };

        flake-devShells = {
          path = ./flake-devShells;
          description = "Template for devShells flake output";
        };

        flake-formatter = {
          path = ./flake-formatter;
          description = "Template for formatter flake output";
        };

        flake-packages = {
          path = ./flake-packages;
          description = "Template for packages flake output";
        };

        flake-overlays = {
          path = ./flake-overlays;
          description = "Template for overlays flake output";
        };

        flake-templates = {
          path = ./flake-templates;
          description = "Template for templates flake output";
        };

        # Complete .flakes root structure
        flakes-root = {
          path = ./flakes-root;
          description = "Complete .flakes directory structure with all output types";
        };

        # Default template
        default = self.templates.flakes-root;
      };
    };
}

