#!/usr/bin/env bash
# Environment variables for the development shell
# This file is sourced by the shell hook

# Rust development environment
export RUST_BACKTRACE="1"
export RUST_LOG="debug"

# Cargo configuration for proper locking
# Cargo will manage Cargo.lock in the project root
# No need to set CARGO_HOME - let cargo use default or system location
