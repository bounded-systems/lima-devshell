# Environment variables for the development environment
# This file defines the development configuration

{
  # Rust development environment
  RUST_BACKTRACE = "1";
  RUST_LOG = "debug";
  
  # Cargo configuration for proper locking
  # Cargo will manage Cargo.lock in the project root
  # No need to set CARGO_HOME - let cargo use default or system location
}

