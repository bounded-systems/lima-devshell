{
  description = "Environment variables configuration";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        packages.default = {
          # Rust development environment
          RUST_BACKTRACE = "1";
          RUST_LOG = "debug";
          
          # Cargo configuration for proper locking
          # Cargo will manage Cargo.lock in the project root
          # No need to set CARGO_HOME - let cargo use default or system location
        };
      }
    );
}

