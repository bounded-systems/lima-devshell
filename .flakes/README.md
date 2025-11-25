# Development Environment

This directory contains a separate Nix flake for local development of the `lima-devshell` project.

## Purpose

The root `flake.nix` is focused on:
- Building the Rust binary for distribution
- Providing the bootstrap devshell for Lima VMs
- Home Manager configuration for macOS

This `.flakes/flake.nix` provides:
- Full Rust development toolchain (rustc, cargo, rustfmt, clippy)
- Development tools (rust-analyzer, gdb, etc.)
- All build dependencies needed for local development

## Usage

### Enter Development Shell

From the `.flakes/` directory:

```bash
cd .flakes
nix develop
```

This will enter a development shell with all Rust tools and dependencies.

### Run Commands Directly

You can also run commands without entering the shell:

```bash
cd .flakes
nix fmt              # Format nix files
nix run .#fmt-rust   # Format Rust code
nix run .#check      # Run all checks
nix run .#test       # Run tests
nix run .#build      # Build release binary
nix flake check      # Check flake validity
```

## Development Workflow

1. **Enter dev shell:**
   ```bash
   cd .flakes
   nix develop
   ```

2. **Build the project:**
   ```bash
   cargo build
   cargo build --release
   ```

3. **Run tests:**
   ```bash
   cargo test
   ```

4. **Format code:**
   ```bash
   cargo fmt
   ```

5. **Run linter:**
   ```bash
   cargo clippy
   ```

6. **Format code:**
   ```bash
   nix fmt          # Format nix files (from .flakes directory)
   nix run .#fmt-rust  # Format Rust code
   ```

7. **Run checks:**
   ```bash
   nix flake check  # Check flake validity
   nix run .#check  # Run all checks (flake, fmt, clippy)
   ```

8. **Run convenience commands:**
   ```bash
   nix run .#test   # Run tests
   nix run .#build  # Build release binary
   ```

9. **Test the flake build** (from project root):
   ```bash
   cd ..
   nix build
   ```

## Referencing from Root Flake

The dev flake exports `devShell` as an output that can be referenced from the root flake:

```nix
# In root flake.nix inputs:
dev = {
  url = "path:./.flakes";
  inputs.nixpkgs.follows = "nixpkgs";
};

# Then use it:
# nix develop .#dev
```

Or reference it directly:
```bash
# From project root
nix develop ./.flakes
```

## Structure

The dev flake separates concerns into clear components:

- **Tooling** (`tooling` variable): Packages like rustc, cargo, clippy, etc.
- **Environment** (`env` variable): Environment variables like RUST_BACKTRACE, RUST_LOG
- **Shell Hook** (`shell-hook.sh` file): Shell initialization script (read via `builtins.readFile`)

This separation allows:
- Easy modification of environment without changing packages
- Easy editing of shell hook without touching the flake
- Reuse of tooling/environment definitions
- Clear distinction between what tools are available vs. how they're configured

### Shell Hook

The shell hook is stored in `.flakes/shell-hook.sh` and read by the flake using `builtins.readFile`. This makes it:
- Easier to edit (no Nix string escaping)
- Syntax-highlighted in editors
- Version-controlled separately from the flake logic

## Cargo Locking

- `Cargo.lock` is gitignored and managed by cargo
- Run `cargo update` to update dependencies and regenerate the lock file
- The lock file is created/updated in the project root during builds
- No special configuration needed - cargo handles locking automatically

## Why Separate?

Separating the dev environment from the root flake keeps concerns clean:
- **Root flake**: Production build, bootstrap shell, Home Manager config
- **Dev flake**: Development tooling, IDE support, testing tools

This separation makes it clear what's needed for building vs. developing.

