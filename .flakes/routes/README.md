# Routes Configuration Directory

This directory stores routing configurations and dependency-related files for the `.flakes/` router system.

## Structure

### Routing Configuration
- **`router-config.json`**: Declarative routing configuration that defines:
  - Subflake definitions (path, output space, required inputs)
  - Input sharing structure (which inputs are shared via `follows`)
  - This serves as the source of truth for router wiring

### Graph & Policy Files
- **`graph-policy.json`**: Refresh policy defining which inputs can be updated and how
- **`flake-lock-schema.json`**: JSON Schema for validating `flake.lock` structure
- **`graph-policy-schema.json`**: JSON Schema for validating policy files
- **`GRAPH-TOOLS.md`**: Documentation for graph-aware tools and usage

## Purpose

This directory centralizes:
- **Routing configuration**: Declarative definition of how subflakes are wired
- **Dependency management**: Refresh policies and update groups
- **Schema definitions**: Validation schemas for lock files and policies

All configuration happens at the router level (`.flakes/flake.nix`), not in individual subflakes.

## Subflake Constraints

### Inputs Directory Rules

- **Most subflakes** (apps, checks, packages, etc.) may have an `inputs/` directory for storing input assets (shell scripts, config files, etc.)
- **The `lib` and `overlays` subflakes** must NOT have an `inputs/` directory because:
  - They are pure helper libraries with no assets
  - All inputs are defined directly in `flake.nix`
  - They only provide functions (lib) or overlay functions (overlays), not scripts or other file-based resources

### Isolation Rules

- Subflakes must not have direct cross-directory dependencies
- All composition happens only in `.flakes/flake.nix` (the sub-router)
- Each subflake owns exactly one top-level output space

## Documentation

- **`GRAPH-TOOLS.md`**: Complete documentation for graph-aware tools, usage, and architecture

## Using router-config.json

The `router-config.json` file documents the routing structure used by `.flakes/flake.nix`. While Nix evaluation is pure and can't dynamically read JSON at evaluation time, this file serves as:

1. **Documentation**: Clear reference for input sharing structure
2. **Validation**: Can be checked against actual router implementation
3. **Future tooling**: Basis for code generation or validation tools

To update routing:
1. Update `router-config.json` to reflect desired structure
2. Update `.flakes/flake.nix` to match the configuration
3. Use validation tools to ensure consistency

