# Git Tips and Workflows

This document describes how `lima-devshell` integrates with Git worktrees and bare repositories.

## Overview

`lima-devshell` is designed to work with Git worktrees organized in an XDG-based directory structure. It automatically discovers worktrees, resolves bare repositories, and mounts both into Lima VMs for seamless development.

## Worktree Structure

### XDG-Based Pattern

`lima-devshell` follows the XDG Base Directory Specification for organizing Git worktrees:

**Host structure:**

```
~/.local/state/git/worktrees/
└── <host>/
    └── <owner>/
        └── <repo>/
            └── <worktree>/
```

**Example:**

```
~/.local/state/git/worktrees/
└── io.github/
    └── owner/
        └── lima-devshell/
            └── main/
```

**XDG directory:**

- **Base**: `~/.local/state/` (or `${XDG_STATE_HOME}`)
- **Purpose**: Ephemeral state files (worktrees)
- **Standard**: Follows XDG Base Directory Specification

### Bare Repository Structure

Bare repositories are stored separately:

**Host structure:**

```
~/.local/share/git/bare/
└── <host>/
    └── <owner>/
        └── <repo>.git/
```

**Example:**

```
~/.local/share/git/bare/
└── io.github/
    └── owner/
        └── lima-devshell.git/
```

**XDG directory:**

- **Base**: `~/.local/share/` (or `${XDG_DATA_HOME}`)
- **Purpose**: Persistent data files (bare repositories)
- **Standard**: Follows XDG Base Directory Specification

## Bare Repository Resolution

The `resolve_bare_repo_path()` function in [`src/git_ctx.rs`](../src/git_ctx.rs) discovers the bare repository from a worktree.

### Resolution Process

1. **Discover repository**: Uses `git2::Repository::discover()` to find the Git repository
2. **Get git directory**: Retrieves the `.git` directory path
3. **Check worktree**: Determines if `.git` is a file (worktree) or directory (regular repo)
4. **Navigate to bare repo**: Traverses up from worktree directory to find bare repo

**For worktrees:**

- `.git` is a file containing `gitdir: <path>`
- Path points to `worktrees/<name>/`
- Navigate up two levels to get bare repo

**For regular repos:**

- `.git` is a directory
- Bare repo is the parent directory

### Implementation

```rust
pub fn resolve_bare_repo_path(target_dir: &Path) -> Result<PathBuf> {
    let repo = Repository::discover(target_dir)
        .context("failed to discover Git repository")?;
    
    let git_dir = repo.path();
    
    // Check if .git is a file (worktree case)
    if git_dir.is_file() {
        let content = fs::read_to_string(git_dir)?;
        if let Some(gitdir) = content.strip_prefix("gitdir: ") {
            let gitdir_path = PathBuf::from(gitdir.trim());
            // Navigate up from worktrees/<name>/ to get bare repo
            if let Some(parent) = gitdir_path.parent().and_then(|p| p.parent()) {
                return Ok(parent.to_path_buf());
            }
        }
    } else if git_dir.is_dir() {
        // Regular repo, bare repo is the parent
        if let Some(parent) = git_dir.parent() {
            return Ok(parent.to_path_buf());
        }
    }
    
    anyhow::bail!("could not determine bare repo path");
}
```

## Instance Naming from Paths

Instance names are derived from worktree path segments using `determine_lima_instance()` in [`src/git_ctx.rs`](../src/git_ctx.rs).

### Naming Rules

**4+ path segments:** `{owner}-{repo}-{worktree}`

```
io.github/owner/repo/worktree → owner-repo-worktree
```

**3 path segments:** `{owner}-{repo}`

```
io.github/owner/repo → owner-repo
```

**2 path segments:** `{segment}`

```
io.github/owner → owner
```

### Implementation

```rust
pub fn determine_lima_instance(path_segments: &[&str]) -> Result<String> {
    match path_segments.len() {
        n if n >= 4 => {
            let repo_owner = path_segments[1];
            let repo_name = path_segments[2];
            let worktree_name = path_segments[3].to_lowercase();
            Ok(format!("{}-{}-{}", repo_owner, repo_name, worktree_name))
        }
        3 => {
            let repo_owner = path_segments[1];
            let repo_name = path_segments[2];
            Ok(format!("{}-{}", repo_owner, repo_name))
        }
        2 => Ok(path_segments[1].to_string()),
        _ => anyhow::bail!("unexpected worktree path structure"),
    }
}
```

### Examples

| Worktree Path | Path Segments | Instance Name |
|---------------|---------------|---------------|
| `io.github/owner/lima-devshell/main` | `["io.github", "owner", "lima-devshell", "main"]` | `owner-lima-devshell-main` |
| `io.github/owner/lima-devshell` | `["io.github", "owner", "lima-devshell"]` | `owner-lima-devshell` |
| `io.github/owner` | `["io.github", "owner"]` | `owner` |

## Git Integration

`lima-devshell` uses the `git2` crate for Git repository operations.

### Repository Discovery

**Function:** `is_git_worktree()` in [`src/git_ctx.rs`](../src/git_ctx.rs)

```rust
pub fn is_git_worktree(dir: &Path) -> Result<bool> {
    match Repository::discover(dir) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}
```

**Purpose:**

- Validates that a directory is inside a Git repository
- Used as a guard before processing

### Worktree Validation

`lima-devshell` includes multiple validation guards:

1. **Host-side validation** (`AppContext::from_args()`):
   - Verifies directory is a Git worktree
   - Checks for `flake.nix` existence
   - Validates path is under worktree root

2. **Guest-side validation** (guest script):
   - Verifies directory is under `/worktrees/`
   - Checks Git worktree status
   - Warns if `flake.nix` is missing

## Worktree Validation

### Guard System

Three levels of validation ensure correct operation:

**1. Host-side (Rust CLI):**

```rust
// Guard 1: Require that we are inside a Git work tree
if !is_git_worktree(&target_dir)? {
    anyhow::bail!("error: current directory is not inside a Git work tree");
}

// Guard 2: Require that flake.nix exists
let flake_path = target_dir.join("flake.nix");
if !flake_path.exists() {
    anyhow::bail!("error: flake.nix not found");
}

// Guard 3: Require that the current directory is under the host worktree root
let host_worktree_root = get_host_worktree_root()?;
let rel_path = get_relative_path(&target_dir, &host_worktree_root)
    .context("current directory is not under the host worktree root")?;
```

**2. In-VM bootstrap (shellHook):**

The bootstrap flake's `shellHook` warns if not in a Git worktree after path mapping.

**3. In-VM validation (guest script):**

```bash
# Guard: Verify we're under the worktrees root
case "$TARGET_DIR" in
  /worktrees/*)
    echo "[lima-devshell] path is under /worktrees/ ✓"
    ;;
  *)
    echo "[lima-devshell] error: target directory is not under /worktrees/" >&2
    exit 1
    ;;
esac

# Guard: Verify we're in a Git worktree
if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[lima-devshell] error: target directory is not inside a Git work tree" >&2
  exit 1
fi
```

## Bare Repository Mounting

Bare repositories are mounted alongside worktrees for Git operations.

### Mount Configuration

**Host location:** Bare repository path (e.g., `~/.local/share/git/bare/io.github/owner/repo.git`)

**Guest mount point:** `/git/bare/{repo-name}.git`

**Writable:** `true` (allows git operations)

### Purpose

- **Git operations**: Enables git commands that need access to the repository
- **Worktree management**: Allows creating additional worktrees from the bare repo
- **Repository access**: Provides full repository access for advanced git operations

### Example

```yaml
mounts:
  - location: /Users/user/.local/share/git/bare/io.github/owner/repo.git
    mountPoint: /git/bare/repo.git
    writable: true
```

## Git Workflows

### Creating Worktrees

**Standard workflow:**

```bash
# Create bare repository
git init --bare ~/.local/share/git/bare/io.github/owner/repo.git

# Create worktree
git -C ~/.local/share/git/bare/io.github/owner/repo.git \
    worktree add ~/.local/state/git/worktrees/io.github/owner/repo/main

# Enter worktree and use lima-devshell
cd ~/.local/state/git/worktrees/io.github/owner/repo/main
lima-devshell
```

### Multiple Worktrees

You can create multiple worktrees from the same bare repository:

```bash
# Create additional worktree
git -C ~/.local/share/git/bare/io.github/owner/repo.git \
    worktree add ~/.local/state/git/worktrees/io.github/owner/repo/feature-branch

# Each worktree gets its own Lima instance
cd ~/.local/state/git/worktrees/io.github/owner/repo/feature-branch
lima-devshell  # Creates instance: owner-repo-feature-branch
```

### Cloning Repositories

**Clone to bare repository:**

```bash
# Clone to bare repository location
git clone --bare https://github.com/owner/repo.git \
    ~/.local/share/git/bare/io.github/owner/repo.git

# Create worktree
git -C ~/.local/share/git/bare/io.github/owner/repo.git \
    worktree add ~/.local/state/git/worktrees/io.github/owner/repo/main
```

### Git Operations in Lima

Once inside the Lima VM, Git operations work normally:

```bash
# Enter Lima instance
lima-devshell

# Inside VM, git commands work as expected
git status
git add .
git commit -m "Changes"
git push
```

**SSH agent forwarding:**

SSH agent forwarding is enabled, so SSH-based git operations work seamlessly:

```yaml
ssh:
  forwardAgent: true
```

## Path Mapping

### Host to Guest Mapping

Paths are mapped consistently:

**Host:** `~/.local/state/git/worktrees/io.github/owner/repo/worktree`  
**Guest:** `/worktrees/io.github/owner/repo/worktree`

**Implementation:**

The mapping is handled by functions in [`src/paths.rs`](../src/paths.rs):

- `get_host_worktree_root()`: Gets host worktree root
- `get_relative_path()`: Computes relative path from root
- `guest_path_for()`: Maps to guest path

### Relative Path Preservation

Relative paths are preserved between host and guest:

```
Host: ~/.local/state/git/worktrees/io.github/owner/repo/worktree/src/main.rs
Guest: /worktrees/io.github/owner/repo/worktree/src/main.rs
```

This ensures that file paths remain consistent across host and guest.

## Best Practices

### Worktree Organization

1. **Use consistent structure**: Follow the XDG-based pattern
2. **Name worktrees clearly**: Use descriptive worktree names (branch names, feature names)
3. **Keep bare repos separate**: Store bare repos in `~/.local/share/git/bare/`

### Instance Naming

1. **Avoid conflicts**: Use unique worktree names to avoid instance name conflicts
2. **Follow conventions**: Use lowercase worktree names (they're lowercased in instance names)
3. **Consider length**: Instance names are derived from path segments, keep them reasonable

### Git Operations

1. **Use SSH**: Configure SSH keys for seamless git operations
2. **Enable agent forwarding**: SSH agent forwarding is enabled by default
3. **Work in worktrees**: Always work in worktrees, not bare repos directly

## Troubleshooting

### Worktree Not Found

**Error:** `error: current directory is not inside a Git work tree`

**Solution:**

- Ensure you're in a Git repository
- Check that `.git` exists (file for worktrees, directory for regular repos)
- Verify git repository discovery works: `git rev-parse --git-dir`

### Bare Repository Not Found

**Error:** `could not determine bare repo path`

**Solution:**

- Check that the worktree's `.git` file points to a valid location
- Verify the bare repository exists at the expected path
- Ensure the worktree was created from a bare repository

### Path Mapping Issues

**Error:** `current directory is not under the host worktree root`

**Solution:**

- Ensure you're in a directory under `~/.local/state/git/worktrees/`
- Check `XDG_STATE_HOME` if using a custom location
- Verify the path is absolute and canonicalized

## See Also

- [`src/git_ctx.rs`](../src/git_ctx.rs) - Git integration implementation
- [`src/paths.rs`](../src/paths.rs) - Path mapping utilities
- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree) - Official Git worktree documentation
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) - XDG directory specification

