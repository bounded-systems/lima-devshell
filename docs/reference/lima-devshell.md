# lima-devshell Command Reference

This document describes the `lima-devshell` command-line interface.

## Synopsis

```bash
lima-devshell [OPTIONS]
```

## Description

`lima-devshell` is a Rust-based CLI tool that manages Lima VM instances for Nix devshell development. It automatically creates, configures, and manages Lima instances based on Git worktree paths, providing a seamless development environment inside Lima VMs.

The command:

1. Validates that you're in a Git worktree under `~/.local/state/git/worktrees/`
2. Maps the host path to `/worktrees/...` in the Lima VM
3. Creates or starts a Lima instance for the worktree
4. Enters the Lima VM and launches the project's Nix devshell

## Options

### `-d, --directory <DIRECTORY>`

Specify the target directory. If not provided, defaults to the current directory.

**Example:**

```bash
lima-devshell --directory ~/.local/state/git/worktrees/io.github/owner/repo/main
```

**Use cases:**

- Running from a different directory
- Scripting and automation
- Testing with specific paths

## Arguments

None. All configuration is derived from the current directory or `--directory` option.

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Error (validation failure, Lima operation failure, etc.) |

## Examples

### Basic Usage

Enter a devshell from the current directory:

```bash
cd ~/.local/state/git/worktrees/io.github/owner/repo/main
lima-devshell
```

### Specify Directory

Enter a devshell from a specific directory:

```bash
lima-devshell --directory ~/.local/state/git/worktrees/io.github/owner/repo/main
```

### From Script

Use in automation scripts:

```bash
#!/bin/bash
cd "$WORKTREE_DIR"
lima-devshell --directory "$WORKTREE_DIR"
```

## Validation Guards

The command includes several validation guards that must pass:

### 1. Git Worktree Check

**Requirement:** Current directory must be inside a Git worktree.

**Error message:**

```
error: current directory is not inside a Git work tree
```

**Solution:**

- Ensure you're in a Git repository
- Check that `.git` exists (file for worktrees, directory for regular repos)
- Verify git repository discovery works: `git rev-parse --git-dir`

### 2. Flake.nix Check

**Requirement:** `flake.nix` must exist in the target directory.

**Error message:**

```
error: flake.nix not found in /path/to/directory
```

**Solution:**

- Create a `flake.nix` file in the directory
- Or navigate to a directory that has a `flake.nix`

### 3. Path Check

**Requirement:** Current directory must be under `~/.local/state/git/worktrees/` (or `${XDG_STATE_HOME}/git/worktrees/`).

**Error message:**

```
error: current directory is not under the host worktree root
```

**Solution:**

- Ensure you're in a directory under the worktree root
- Check `XDG_STATE_HOME` if using a custom location
- Verify the path is absolute and canonicalized

## Behavior

### Instance Creation

If the Lima instance doesn't exist, `lima-devshell` will:

1. Generate a `lima.yaml` configuration file
2. Create the Lima instance
3. Start the instance
4. Wait for the instance to be ready (guest agent connected)

### Instance Management

If the instance exists but isn't running:

1. Stop the existing instance (best effort)
2. Delete the instance to ensure clean state
3. Create a new instance with fresh configuration

**Why delete and recreate:**

- Prevents issues with stale/cached YAML configurations
- Ensures instance matches current worktree state
- Provides clean state for each run

### Instance Naming

Instance names are derived from the worktree path:

- **4+ path segments:** `{owner}-{repo}-{worktree}`
- **3 path segments:** `{owner}-{repo}`
- **2 path segments:** `{segment}`

**Example:**

```
Path: io.github/owner/repo/main
Instance: owner-repo-main
```

### Path Mapping

Paths are mapped from host to guest:

**Host:** `~/.local/state/git/worktrees/io.github/owner/repo/main`  
**Guest:** `/worktrees/io.github/owner/repo/main`

### State Files

A `.lima-devshell` file is created in the worktree directory containing the instance name:

```
<worktree>/.lima-devshell
```

**Content:** Single line with the instance name (e.g., `owner-repo-main`)

**Purpose:** Allows tools like `direnv` to discover which Lima instance to use.

### Guest Script Execution

Once the instance is ready, `lima-devshell` executes a bash script inside the VM that:

1. Validates the target directory is under `/worktrees/`
2. Verifies the directory is a Git worktree
3. Checks for `flake.nix` (warning if missing)
4. Changes to the target directory
5. Launches the project devshell via `nix develop`

## Output

### Standard Output

The command prints progress information:

```
lima-devshell: host:  /Users/user/.local/state/git/worktrees/io.github/owner/repo/main
lima-devshell: guest: /worktrees/io.github/owner/repo/main
lima-devshell: instance: owner-repo-main
lima-devshell: bare repo: /Users/user/.local/share/git/bare/io.github/owner/repo.git
lima-devshell: wrote instance name to .lima-devshell
lima-devshell: wrote lima.yaml to /Users/user/.local/state/git/worktrees/io.github/owner/repo/main/lima.yaml
lima-devshell: ensuring Lima instance 'owner-repo-main' is created and running...
lima-devshell: waiting for instance 'owner-repo-main' to be ready...
lima-devshell: instance 'owner-repo-main' is ready
[lima-devshell] target directory: /worktrees/io.github/owner/repo/main
[lima-devshell] path is under /worktrees/ ✓
[lima-devshell] now in: /worktrees/io.github/owner/repo/main
[lima-devshell] launching project devshell...
```

### Standard Error

Error messages are printed to stderr:

```
lima-devshell: error: current directory is not inside a Git work tree
```

## Environment Variables

The command respects the following environment variables:

### `LIMA_HOME`

Lima home directory. Defaults to `~/.lima` if not set.

**Example:**

```bash
export LIMA_HOME=~/custom/lima
lima-devshell
```

### `XDG_STATE_HOME`

XDG state home directory. Defaults to `~/.local/state` if not set.

**Example:**

```bash
export XDG_STATE_HOME=~/custom/state
lima-devshell
```

### `HOME`

Home directory. Used for default paths if `LIMA_HOME` or `XDG_STATE_HOME` are not set.

## Integration

### With direnv

The `.lima-devshell` file can be used by `direnv` to discover the Lima instance:

```bash
# In .envrc
if [ -f .lima-devshell ]; then
    export LIMA_INSTANCE=$(cat .lima-devshell)
fi
```

### With Scripts

Use in automation scripts:

```bash
#!/bin/bash
set -e

WORKTREE_DIR="$1"
cd "$WORKTREE_DIR"
lima-devshell --directory "$WORKTREE_DIR"
```

### With CI/CD

For CI/CD environments:

```bash
# Ensure Lima is installed
# Ensure virtualization is available (QEMU/KVM for Linux)

# Create test worktree
mkdir -p ~/.local/state/git/worktrees/test/owner/repo
cd ~/.local/state/git/worktrees/test/owner/repo

# Create minimal flake
cat > flake.nix <<EOF
{
  outputs = { self, nixpkgs }: {
    devShells.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {};
  };
}
EOF

# Run lima-devshell
lima-devshell || true

# Cleanup
limactl delete --force test-owner-repo || true
```

## Troubleshooting

### Instance Creation Fails

**Error:** `failed to start Lima instance`

**Solutions:**

- Check Lima installation: `limactl --version`
- Verify virtualization support (QEMU/KVM for Linux, Virtualization.framework for macOS)
- Check disk space: `df -h`
- Review Lima logs: `~/.lima/<instance>/ha.stderr.log`

### Instance Not Ready

**Error:** `instance did not become ready within 60 seconds`

**Solutions:**

- Check instance status: `limactl list`
- Review instance logs: `~/.lima/<instance>/ha.stderr.log`
- Try manual start: `limactl start <instance>`
- Check guest agent: `limactl shell <instance> -- systemctl status lima-guestagent`

### Path Mapping Issues

**Error:** `current directory is not under the host worktree root`

**Solutions:**

- Ensure you're in a directory under `~/.local/state/git/worktrees/`
- Check `XDG_STATE_HOME` if using a custom location
- Verify the path is absolute: `pwd`

### Git Worktree Issues

**Error:** `error: current directory is not inside a Git work tree`

**Solutions:**

- Verify you're in a Git repository: `git rev-parse --git-dir`
- Check `.git` exists (file for worktrees, directory for regular repos)
- Ensure git repository is valid: `git status`

## See Also

- [`limactl-devshell`](./limactl-devshell.md) - Plugin wrapper reference
- [Lima Command Reference](https://lima-vm.io/docs/reference/) - Official Lima command documentation
- [`src/app.rs`](../../src/app.rs) - Command implementation
- [`src/lima.rs`](../../src/lima.rs) - Instance management

