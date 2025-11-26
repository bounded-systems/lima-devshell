# This flake owns only the `lib` output space.
# It may depend on: nixpkgs, flake-utils (pure utility libraries).
# It must not import from other .flakes/* directories.
# This is a pure helper library with no project-space knowledge.
{
  description = "Pure helper functions and utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Import nixpkgs for lib access (we only need lib, not packages)
      lib = nixpkgs.lib;
      # Standard systems list for cross-platform flakes
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      lib = {
        # Standard systems list (re-exported for convenience)
        inherit systems;
        
        # Re-export flake-utils helpers for convenience
        inherit (flake-utils.lib) eachDefaultSystem eachSystem;
        
        # Helper to apply a function to all systems (alias for eachDefaultSystem)
        # Usage: perSystem (system: { ... })
        perSystem = f: lib.genAttrs systems f;
        
        # Helper to get nixpkgs for a specific system
        # Usage: pkgsFor system
        pkgsFor = system: import nixpkgs { inherit system; };
        
        # Helper to create a tool substitution mapping
        # Converts { tool = pkg; ... } to { TOOL_BIN = "${pkg}/bin"; ... }
        # Usage: mkToolSubstitutions { cargo = pkgs.cargo; jq = pkgs.jq; }
        mkToolSubstitutions = tools:
          lib.mapAttrs' 
            (name: pkg: lib.nameValuePair "${lib.toUpper name}_BIN" "${pkg}/bin")
            tools;
        
        # Helper to replace variables in a string
        # Usage: replaceVars "${VAR1} and ${VAR2}" { VAR1 = "value1"; VAR2 = "value2"; }
        replaceVars = content: vars:
          lib.foldl' (acc: varName:
            let varValue = vars.${varName}; in
            lib.replaceStrings ["${" + varName + "}"] [varValue] acc
          ) content (lib.attrNames vars);
        
        # Helper to read and process a file with variable substitution
        # Usage: readAndSubstitute filePath { VAR = "value"; }
        readAndSubstitute = filePath: vars:
          self.lib.replaceVars (builtins.readFile filePath) vars;
        
        # Helper to create a simple app from a script path
        # Usage: mkApp name scriptPath description
        mkApp = name: scriptPath: description: {
          type = "app";
          meta = { inherit description; };
          program = toString scriptPath;
        };
        
        # Helper to create a check that runs a command
        # Usage: mkCheck name { nativeBuildInputs = [...]; } "command to run"
        mkCheck = name: buildInputs: command:
          (import nixpkgs { system = "x86_64-linux"; }).runCommand name buildInputs command;
      };
    };
}

