# Flake Graph Tools

This document describes graph-aware tooling for managing flake input graphs with schema validation. All related configuration files are stored in `.flakes/routes/`.

## Overview

The graph tools provide:
- **Schema validation** of `flake.lock` against JSON Schema
- **Node classification** (internal path nodes vs external git/github nodes)
- **Graph-aware refresh** that respects isolation constraints
- **Graph visualization** in multiple formats (JSON, Mermaid, DOT)

## Configuration Files

All configuration, schema, and policy files are stored in `.flakes/routes/`:

### Routing Configuration
- **`router-config.json`**: Declarative routing configuration defining subflake structure and input sharing
- **`router-config-schema.json`**: JSON Schema for validating router configuration

### Graph & Policy Files
- **`graph-policy.json`**: Refresh policy defining which inputs can be updated and how
- **`flake-lock-schema.json`**: JSON Schema for validating `flake.lock` structure
- **`graph-policy-schema.json`**: JSON Schema for validating policy files

The router also uses **Determinate Systems flake-schemas** for flake output validation.

## Tools

### `graph-refresh`

Graph-aware flake lock refresh tool that:
1. Validates `flake.lock` against schema
2. Classifies nodes (internal vs external)
3. Applies refresh policy to determine which inputs to update
4. Updates only mutable external nodes
5. Re-validates after update

**Usage:**
```bash
# Update default group (from graph-policy.json)
nix run .#graph-refresh

# Update specific group
nix run .#graph-refresh -- --group toolchain

# Update subtree (all descendants of a node)
nix run .#graph-refresh -- --subtree nixpkgs

# Dry run (show what would be updated)
nix run .#graph-refresh -- --dry-run

# Validate only (check schema without updating)
nix run .#graph-refresh -- --validate-only
```

### `graph-show`

Visualize the flake input graph in various formats.

**Usage:**
```bash
# JSON format (default)
nix run .#graph-show

# Mermaid diagram format
nix run .#graph-show mermaid

# DOT format (Graphviz)
nix run .#graph-show dot
```

## Router Configuration

The `router-config.json` file documents the routing structure used by `.flakes/flake.nix`:
- **Subflakes**: Definitions of each subflake (path, output space, required inputs)
- **Shared Inputs**: Which inputs are shared via `follows` and which subflakes use them

This serves as documentation and can be used for validation and future tooling.

## Graph Policy

The `graph-policy.json` file defines:
- **Groups**: Named collections of inputs that can be updated together
- **Immutable**: Inputs that should never be updated (internal path inputs)
- **Default group**: Group to update when no group is specified

Example policy:
```json
{
  "groups": {
    "toolchain": ["nixpkgs", "crane"],
    "ci": ["cachix", "hercules-ci-agent"]
  },
  "immutable": ["project-root"],
  "defaultGroup": "toolchain"
}
```

## Checks

The `graph-structure-check` in `.flakes/checks/flake.nix` validates:
- `flake.lock` structure against schema
- All `.flakes/*` nodes are internal path nodes (not git/github)
- Graph structure respects isolation constraints

Run as part of `nix flake check`:
```bash
nix flake check
```

## Schema Validation

Schema validation uses Python's `jsonschema` library. To enable full validation:

```bash
# Install jsonschema (if not already available)
pip install jsonschema

# Or use nix-shell
nix-shell -p python3Packages.jsonschema
```

If `jsonschema` is not available, the tools will skip validation but still function.

## Architecture

The graph tools respect the isolation constraints:
- **Read-only**: Tools only read `flake.lock` and policy files; they don't import sibling flake outputs
- **Router-level**: Tools live at `.flakes/flake.nix` router level, not in individual subflakes
- **No cross-dir deps**: Tools don't create dependencies between subflakes

This makes the graph infrastructure **global** rather than a dependency between inner flakes.

