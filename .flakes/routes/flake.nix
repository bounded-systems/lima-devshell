# Core routing flake
# Provides routing utilities and functions that can be used by .flakes/flake.nix
# This centralizes routing logic and makes the router more maintainable.
{
  description = "Core routing utilities for .flakes/ router";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Project root for reading router-config.json
    project-root.url = "path:../..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, project-root }:
    let
      lib = nixpkgs.lib;
      projectRoot = toString project-root;
      routerConfigPath = "${projectRoot}/.flakes/routes/router-config.json";

      # Read router config if it exists
      routerConfig =
        if builtins.pathExists routerConfigPath
        then builtins.fromJSON (builtins.readFile routerConfigPath)
        else { subflakes = { }; sharedInputs = { }; };

      # Extract subflake definitions
      subflakes = routerConfig.subflakes or { };
      sharedInputs = routerConfig.sharedInputs or { };

    in
    {
      lib = {
        # Get list of all subflake names
        getSubflakeNames = lib.attrNames subflakes;

        # Get subflake path by name
        getSubflakePath = name: (subflakes.${name} or { }).path or null;

        # Get output space for a subflake
        getOutputSpace = name: (subflakes.${name} or { }).outputSpace or null;

        # Get required inputs for a subflake
        getRequiredInputs = name: (subflakes.${name} or { }).requiredInputs or [ ];

        # Get all followers for a shared input
        getFollowers = inputName: (sharedInputs.${inputName} or { }).followers or [ ];

        # Get source input name for a shared input
        getSource = inputName: (sharedInputs.${inputName} or { }).source or inputName;

        # Check if an input should be shared with a subflake
        shouldShareInput = inputName: subflakeName:
          let
            followers = self.lib.getFollowers inputName;
            followerPath = "${subflakeName}.inputs.${inputName}";
          in
          lib.elem followerPath followers;

        # Get all subflakes that need a specific input
        getSubflakesNeedingInput = inputName:
          lib.filter
            (name:
              lib.elem inputName (self.lib.getRequiredInputs name)
            )
            (self.lib.getSubflakeNames);

        # Router config for reference
        routerConfig = routerConfig;

        # Helper to build input follows structure
        # Returns an attrset suitable for use in flake inputs
        buildFollows = inputName:
          let
            followers = self.lib.getFollowers inputName;
            # Convert "apps-flake.inputs.nixpkgs" to { "apps-flake" = { inputs = { nixpkgs = { follows = "nixpkgs"; }; }; }; }
            buildFollower = follower:
              let
                parts = lib.splitString "." follower;
                flakeName = lib.head parts;
                inputPath = lib.tail parts;
              in
              if lib.length inputPath == 2 && lib.elemAt inputPath 0 == "inputs"
              then {
                ${flakeName} = {
                  inputs = {
                    ${lib.elemAt inputPath 1} = {
                      follows = inputName;
                    };
                  };
                };
              }
              else { };

            # Merge all follower configs
            merged = lib.foldlAttrs
              (acc: name: value:
                lib.recursiveUpdate acc value
              )
              { }
              (map buildFollower followers);
          in
          merged;
      };
    };
}

