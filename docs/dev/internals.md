# Internal Data Structure

This document describes the internal architecture and data structures of `lima-devshell`.

## Overview

`lima-devshell` is a Rust-based CLI tool that manages Lima VM instances for Nix devshell development. It automatically creates, configures, and manages Lima instances based on Git worktree paths, providing a seamless development environment inside Lima VMs.

## Lima Instance Directory Structure

When `lima-devshell` creates a Lima instance, it follows Lima's standard directory structure:

### Instance Directory (`${LIMA_HOME}/<INSTANCE>`)

Each instance is stored in `~/.lima/<instance-name>/` (or `${LIMA_HOME}/<instance-name>/` if `LIMA_HOME` is set).

**Key files and directories:**

- `lima.yaml`: The YAML configuration file for this instance (generated dynamically by `lima-devshell`)
- `basedisk`: The base disk image (QCOW2 format)
- `diffdisk`: The diff disk image (QCOW2 format) containing instance-specific changes
- `ssh.config`: SSH configuration file for connecting to the instance
- `ssh.sock`: SSH control master socket
- `ha.pid`: Host agent process ID
- `ha.sock`: Host agent REST API socket
- `ha.stdout.log`: Host agent stdout (JSON lines)
- `ha.stderr.log`: Host agent stderr (human-readable messages)
- `ga.sock`: Guest agent socket (forwarded to `/run/lima-guestagent.sock` in the guest)

For more details on Lima's internal structure, see the [Lima Internal Data Structure documentation](https://lima-vm.io/docs/dev/internals/).

## Configuration Files

### `lima.yaml` Generation

The `lima.yaml` file is generated dynamically for each instance by the `generate_lima_yaml_impl()` function in [`src/lima.rs`](../src/lima.rs).

**Generation process:**

1. **VM type detection**: Uses `detect_vm_type()` to select `vz` (macOS), `qemu` (Linux), or `wsl2` (Windows)
2. **Architecture detection**: Uses `detect_arch()` to map host architecture to VM architecture
3. **Image selection**: Selects Ubuntu 24.04 cloud image based on architecture
4. **Mount configuration**: Adds worktree and bare repository mounts
5. **Resource allocation**: Sets CPU, memory, and disk defaults
6. **SSH configuration**: Configures SSH with auto-assigned port and agent forwarding
7. **Guest agent**: Enables guest agent for MCP (Model Context Protocol) support
8. **Rosetta**: Enables Rosetta on macOS ARM for Intel-on-ARM emulation

**Example generated `lima.yaml`:**

```yaml
# Lima instance for repo-name development
vmType: vz
arch: aarch64
images:
  - location: https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img
    arch: aarch64
mounts:
  - location: /Users/user/.local/state/git/worktrees/io.github/owner/repo/worktree
    mountPoint: /worktrees/io.github/owner/repo/worktree
    writable: true
  - location: /Users/user/.local/share/git/bare/io.github/owner/repo.git
    mountPoint: /git/bare/repo.git
    writable: true
memory: 6GiB
cpus: 4
disk: 80GiB
ssh:
  localPort: 0
  loadDotSSHPubKeys: true
  forwardAgent: true
env:
  LIMA_WORKDIR_DISABLED: "1"
provision:
  - mode: system
    script: |
      #!/bin/sh
      # Create user if not present
      if ! id dev >/dev/null 2>&1; then
        useradd -m -s /bin/bash dev
        passwd -d dev
        usermod -aG sudo dev
      fi
guestAgent:
  enabled: true
  logPath: /var/log/lima-guest-agent.log
rosetta:
  enabled: true
  binfmt: true
mountType: virtiofs
mountInotify: true
```

### Template Usage

The base template (`lima-devshell-template.yaml`) provides default configuration values. The Rust code in [`src/lima.rs`](../src/lima.rs) customizes this template per instance by:

- Adding dynamic mounts for worktrees and bare repos
- Setting instance-specific paths
- Configuring resource allocation (CPU, memory, disk)
- Enabling platform-specific features (Rosetta, virtiofs)

## Path Mapping

`lima-devshell` uses a consistent path mapping between host and guest:

### Host Path Structure

```
~/.local/state/git/worktrees/
└── io.github/
    └── owner/
        └── repo/
            └── worktree/
```

### Guest Path Structure

```
/worktrees/
└── io.github/
    └── owner/
        └── repo/
            └── worktree/
```

**Mapping logic:**

- Host root: `~/.local/state/git/worktrees/` (or `${XDG_STATE_HOME}/git/worktrees/`)
- Guest root: `/worktrees/`
- Relative paths are preserved between host and guest

**Implementation:**

The path mapping is handled by functions in [`src/paths.rs`](../src/paths.rs):

- `get_host_worktree_root()`: Gets the host worktree root directory
- `get_relative_path()`: Computes relative path from worktree root
- `guest_path_for()`: Maps relative path to guest path

## Instance Naming

Instance names are derived from Git worktree paths using the `determine_lima_instance()` function in [`src/git_ctx.rs`](../src/git_ctx.rs).

### Naming Rules

1. **4+ path segments**: `{owner}-{repo}-{worktree}`
   - Example: `io.github/owner/repo/worktree` → `owner-repo-worktree`

2. **3 path segments**: `{owner}-{repo}`
   - Example: `io.github/owner/repo` → `owner-repo`

3. **2 path segments**: `{segment}`
   - Example: `io.github/owner` → `owner`

### Path Segment Structure

The expected path structure is:
```
<worktree-root>/<segment1>/<segment2>/<segment3>/...
```

For typical GitHub repositories:
- `segment1`: `io.github` (or other host identifier)
- `segment2`: Repository owner
- `segment3`: Repository name
- `segment4+`: Worktree name (optional)

## Mount Structure

Each Lima instance has two mounts:

### 1. Worktree Mount

- **Host location**: The worktree directory (e.g., `~/.local/state/git/worktrees/io.github/owner/repo/worktree`)
- **Guest mount point**: Mapped to `/worktrees/...` preserving the relative path
- **Writable**: `true` (allows file modifications)
- **Purpose**: Provides access to the project files inside the VM

### 2. Bare Repository Mount

- **Host location**: The bare Git repository (e.g., `~/.local/share/git/bare/io.github/owner/repo.git`)
- **Guest mount point**: `/git/bare/{repo-name}.git`
- **Writable**: `true` (allows git operations)
- **Purpose**: Provides access to the Git repository for git operations

**Mount type selection:**

- **macOS with VZ**: Uses `virtiofs` (requires macOS 13+)
- **Others**: Uses Lima defaults (9p for QEMU, virtiofs for VZ)

## State Files

### `.lima-devshell` File

A `.lima-devshell` file is created in each worktree directory containing the Lima instance name:

```
<worktree>/.lima-devshell
```

**Content:** Single line with the instance name (e.g., `owner-repo-worktree`)

**Purpose:** Allows tools like `direnv` to discover which Lima instance to use for a given worktree.

**Creation:** Written by `ensure_instance()` in [`src/lima.rs`](../src/lima.rs) before creating the Lima instance.

### Instance Metadata

Lima stores instance metadata in the instance directory:

- `lima-version`: The Lima version used to create the instance
- `lima.yaml`: The YAML configuration (generated by `lima-devshell`)
- `protected`: Empty file if instance is protected (not used by `lima-devshell`)

## Rust Code Structure

The `lima-devshell` codebase is organized into the following modules:

### `src/main.rs`

Entry point that calls `app::run()`.

### `src/app.rs`

Main application logic:

- **`Args`**: CLI argument parsing using `clap`
- **`AppContext`**: Context containing all derived information about the target directory
- **`InstanceModel`**: Model describing what mounts and configuration a Lima instance needs
- **`run()`**: Main orchestration function

**Key functions:**

- `AppContext::from_args()`: Builds context from CLI arguments, including validation guards
- `InstanceModel::from_context()`: Builds instance model from context
- `run()`: Orchestrates instance creation and devshell entry

### `src/lima.rs`

Lima VM configuration and instance management:

- **VM configuration**: VM type detection, architecture detection, image selection
- **YAML generation**: `generate_lima_yaml_impl()` creates Lima YAML configurations
- **Instance lifecycle**: `ensure_instance()`, `start_lima_instance_with_yaml()`, `stop_lima_instance()`, `delete_lima_instance()`
- **Instance readiness**: `wait_for_instance_ready()` waits for guest agent connection
- **Devshell entry**: `enter_devshell()` executes the guest script

**Key constants:**

- `MEMORY`: `"6GiB"`
- `CPUS`: `4`
- `DISK`: `"80GiB"`

### `src/git_ctx.rs`

Git repository discovery and worktree handling:

- **`is_git_worktree()`**: Checks if a directory is inside a Git worktree
- **`resolve_bare_repo_path()`**: Resolves the bare repository path from a worktree
- **`determine_lima_instance()`**: Determines Lima instance name from path segments

**Git integration:**

Uses the `git2` crate for repository discovery and worktree detection.

### `src/paths.rs`

Path mapping utilities:

- **`GUEST_WORKTREE_ROOT`**: Constant `"/worktrees"`
- **`xdg_state_home()`**: Gets XDG_STATE_HOME directory
- **`get_host_worktree_root()`**: Gets the host worktree root directory
- **`get_relative_path()`**: Computes relative path from root
- **`guest_path_for()`**: Maps relative path to guest path

### `src/script.rs`

Guest script generation:

- **`BOOTSTRAP_FLAKE_PATH`**: Path to bootstrap flake in guest (`/worktrees/io.github/bdelanghe/lima-devshell`)
- **`build_guest_script()`**: Builds the bash script that runs inside the Lima VM

**Guest script responsibilities:**

1. Validates target directory is under `/worktrees/`
2. Verifies the directory is a Git worktree
3. Checks for `flake.nix` (warning if missing)
4. Changes to target directory
5. Launches project devshell (via bootstrap flake or direct `nix develop`)

## Instance Lifecycle

### Creation Flow

1. **Validation**: `AppContext::from_args()` validates:
   - Current directory is a Git worktree
   - `flake.nix` exists
   - Directory is under worktree root

2. **Context building**: Builds `AppContext` and `InstanceModel` from validated input

3. **Instance check**: `ensure_instance()` checks if instance exists and is running

4. **Cleanup**: If instance exists but isn't running, stops and deletes it for clean state

5. **YAML generation**: Generates `lima.yaml` in worktree directory

6. **Instance creation**: `start_lima_instance_with_yaml()` creates and starts instance

7. **Readiness wait**: `wait_for_instance_ready()` waits for guest agent connection

8. **State file**: Writes `.lima-devshell` file with instance name

### Devshell Entry Flow

1. **Script generation**: `build_guest_script()` generates bash script for guest

2. **Script execution**: `enter_devshell()` executes script via `limactl shell`

3. **Guest validation**: Script validates environment inside VM

4. **Devshell launch**: Script launches project devshell via `nix develop`

## Error Handling

`lima-devshell` uses `anyhow` for error handling:

- **Context propagation**: Errors include context about what operation failed
- **User-friendly messages**: Error messages are clear and actionable
- **Guard failures**: Validation guards exit early with clear error messages

**Common error scenarios:**

- Not in a Git worktree
- `flake.nix` not found
- Directory not under worktree root
- Lima instance creation/startup failures
- Guest script execution failures

## See Also

- [Lima Internal Data Structure](https://lima-vm.io/docs/dev/internals/) - Official Lima documentation
- [`src/lima.rs`](../src/lima.rs) - VM configuration implementation
- [`src/app.rs`](../src/app.rs) - Application logic
- [`src/git_ctx.rs`](../src/git_ctx.rs) - Git integration
- [`src/paths.rs`](../src/paths.rs) - Path mapping
- [`src/script.rs`](../src/script.rs) - Guest script generation

