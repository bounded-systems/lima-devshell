# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Purpose

This is a **bootstrap flake** for Lima VM environments—not a project devshell. It provides minimal tooling (nix, git, curl, direnv) to enable running `nix develop` on actual project flakes inside the Lima VM. Think of it as a launcher, not a development environment itself.

## Common Commands

### Testing the Flake
```bash
# Build and enter the bootstrap shell (on Linux only - x86_64 or aarch64)
nix develop

# Check flake configuration
nix flake show
nix flake check
```

### Inside Lima VM Usage
```bash
# Option 1: Use local flake path
nix develop ~/lima-devshell

# Option 2: Use GitHub URL (requires network)
nix develop github:bdelanghe/lima-devshell

# Then navigate to actual project and run its devshell
cd /worktrees/io.github/pushd/percy/COMMERCE-4873
nix develop .
```

### From macOS Host
The `lima-devshell` command (defined in Home Manager) automates entry:
```bash
# Navigate to a git worktree under ~/.local/state/git/worktrees/
cd ~/.local/state/git/worktrees/io.github/pushd/percy/COMMERCE-4873

# Command validates path, maps to Lima /worktrees, and enters project devshell
lima-devshell
```

## Architecture

### Two-Layer Design
1. **Bootstrap layer** (this flake): Provides nix, git, curl, cacert, bash, direnv
2. **Project layer**: The actual devshells in Percy, dx-compose, etc.

The bootstrap layer exists only to make the project layer accessible inside Lima VMs.

### Path Mapping Contract
- **Host**: `~/.local/state/git/worktrees/` (XDG-style worktree storage)
- **Lima VM**: `/worktrees/` (mounted Lima volume)

All path guards and helper scripts depend on this mapping being consistent.

### Guard System
Three levels of validation:
1. **Host-side** (`lima-devshell` command): Verifies you're in a git worktree under `~/.local/state/git/worktrees/`
2. **In-VM bootstrap** (flake.nix shellHook): Warns if not in git worktree after path mapping
3. **Helper script** (bin/enter-project-devshell.sh): Validates worktrees root, git status, and flake.nix existence

### Key Files

**flake.nix**
- Only supports `x86_64-linux` and `aarch64-linux` (Lima VM architectures)
- Single `default` devShell with minimal packages
- shellHook sets `NIX_CONFIG` for flakes/nix-command, exports `WORKTREES=/worktrees`
- References helper script at `/worktrees/io.github/bdelanghe/lima-devshell/bin/enter-project-devshell.sh`

**bin/enter-project-devshell.sh**
- Bash helper for entering project devshells from bootstrap shell
- Validates target directory is under `/worktrees` and is a git worktree
- Warns if no flake.nix found but continues anyway
- Executes `nix develop` in target directory

### Repository Structure (XDG Pattern)
- **Bare repo**: `~/.local/share/git/bare/io.github/bdelanghe/lima-devshell.git/`
- **Worktree**: `~/.local/state/git/worktrees/io.github/bdelanghe/lima-devshell/`

This follows the same pattern used for other repos under `~/.local/state/git/worktrees/`.

## Development Constraints

### Platform Limitations
This flake is **Linux-only**. Do not add macOS or Windows systems to the `systems` list. The bootstrap environment runs inside Lima VMs, which are Linux.

### Package Minimalism
Only add packages that are absolutely necessary to *reach* project devshells. This is not a general-purpose development environment. Resist adding language toolchains, build tools, or project-specific utilities here.

### Environment Variables
The bootstrap shell sets:
- `NIX_CONFIG="experimental-features = nix-command flakes"` - Required for modern Nix
- `WORKTREES=/worktrees` - Standard worktree root in Lima
- `LIMA_DEVSHELL_SCRIPT` - Path to helper script

Do not add project-specific environment variables here.

### Helper Script Expectations
`bin/enter-project-devshell.sh` must:
- Accept optional directory argument (defaults to pwd)
- Validate paths are under `/worktrees`
- Verify git worktree status
- Use `exec nix develop` as the final command (replaces shell process)

## Testing Changes

Since this runs in Lima VMs, testing requires:
1. Build locally: `nix develop` (requires Linux or Lima VM)
2. Commit and push changes
3. From macOS, navigate to a project worktree
4. Run `lima-devshell` to test path mapping and bootstrap → project transition

There are no automated tests. Validation is manual via the guard system.
