# lima-devshell

Bootstrap devshell for Lima VM environments. This flake provides just enough tools (nix, git, curl, etc.) to run `nix develop` on project devshells inside the Lima VM.

## Purpose

This is a **bootstrap flake**, not a project devshell. Its only job is to provide minimal tooling needed to launch the "real" devshells defined in your project flakes (Percy, dx, etc.).

## What It Provides

- `nix` - Nix CLI for running `nix develop` on project flakes
- `git` - Basic git operations
- `curl` - Fetching things if needed
- `cacert` - TLS certificate bundle
- `bashInteractive` - Interactive bash shell
- `direnv` - Environment variable management

## Usage

### Inside Lima VM

After entering the Lima VM, you can use this flake to bootstrap into project devshells:

```bash
# Option 1: Use the flake directly
nix develop ~/lima-devshell

# Option 2: Use flake URL (if you have network access)
nix develop github:bdelanghe/lima-devshell

# Then navigate to your project and run its devshell
cd /worktrees/io.github/pushd/percy/COMMERCE-4873
nix develop .
```

### From macOS (via lima-devshell command)

The `lima-devshell` command (defined in Home Manager) automatically:
1. Validates you're in a Git worktree under `~/.local/state/git/worktrees/`
2. Maps the host path to `/worktrees/...` in Lima
3. Enters Lima and runs `nix develop` on the project flake

```bash
cd ~/.local/state/git/worktrees/io.github/pushd/percy/COMMERCE-4873
lima-devshell  # Automatically enters Lima and runs nix develop
```

## Guard Behavior

The `lima-devshell` command includes safety guards:

1. **Git worktree check**: Verifies you're inside a Git worktree
2. **Path mapping check**: Ensures your current directory is under `~/.local/state/git/worktrees/`
3. **In-VM check**: The bootstrap flake's shellHook warns if not in a Git worktree after path mapping

If guards fail, the command exits with clear error messages before launching Lima.

## Environment Variables

The bootstrap shell sets:
- `NIX_CONFIG="experimental-features = nix-command flakes"` - Enables modern Nix features
- `WORKTREES=/worktrees` - Common worktree root inside Lima

## Repository Structure

- **Bare repo**: `~/.local/share/git/bare/io.github/bdelanghe/lima-devshell.git/`
- **Worktree**: `~/.local/state/git/worktrees/io.github/bdelanghe/lima-devshell/`

Follows the same XDG-based git worktree pattern as other repos.

