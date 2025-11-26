# Inputs Directory

This directory stores input-related configuration and documentation for the `apps` subflake.

## Purpose

- **Input documentation**: Document what each input is used for
- **Input validation**: Schema or validation rules for inputs
- **Input metadata**: Version constraints, update policies, etc.

## Structure

Each input can have its own file or directory:
- `nixpkgs.md` - Documentation for nixpkgs input
- `project-root.md` - Documentation for project-root input
- `inputs.json` - Structured metadata about all inputs

## Isolation Rule

This directory is for **documentation and metadata only**. It does NOT create dependencies between subflakes. All actual input wiring happens in the router (`.flakes/flake.nix`).

