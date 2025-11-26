# Virtual Machine Drivers

This document describes how `lima-devshell` uses Lima's virtual machine drivers and configures VM resources.

## Overview

`lima-devshell` does not create custom VM drivers. Instead, it uses Lima's built-in drivers (`vz`, `qemu`, `wsl2`) and automatically selects the appropriate driver based on the host platform.

## VM Type Detection

The `detect_vm_type()` function in [`src/lima.rs`](../src/lima.rs) automatically selects the VM type:

```rust
fn detect_vm_type() -> &'static str {
    match std::env::consts::OS {
        "macOS" => "vz",
        "linux" => "qemu",
        "windows" => "wsl2",
        _ => "qemu", // Default fallback
    }
}
```

### VM Type Selection

| Host OS | VM Type | Notes |
|---------|---------|-------|
| macOS | `vz` | Uses Virtualization.framework (macOS 13+), best performance |
| Linux | `qemu` | Standard QEMU/KVM virtualization |
| Windows | `wsl2` | Uses WSL2 backend (experimental) |

**macOS (`vz`):**

- **Requirements**: macOS 13.0+ (Ventura or later)
- **Performance**: Native hypervisor, best performance on macOS
- **Features**: Supports Rosetta for Intel-on-ARM emulation
- **Mount type**: Uses `virtiofs` for file system mounts (requires macOS 13+)

**Linux (`qemu`):**

- **Requirements**: QEMU/KVM support
- **Performance**: Hardware-accelerated virtualization via KVM
- **Mount type**: Uses `9p` for file system mounts (default)

**Windows (`wsl2`):**

- **Status**: Experimental in Lima
- **Requirements**: WSL2 installed and configured
- **Use case**: Primarily for development/testing

## Architecture Detection

The `detect_arch()` function maps host architecture to VM architecture:

```rust
fn detect_arch() -> &'static str {
    match std::env::consts::ARCH {
        "aarch64" | "arm64" => "aarch64",
        "x86_64" => "x86_64",
        _ => "x86_64", // Default fallback
    }
}
```

### Architecture Mapping

| Host Architecture | VM Architecture | Notes |
|-------------------|-----------------|-------|
| `aarch64` / `arm64` | `aarch64` | ARM64 (Apple Silicon, ARM servers) |
| `x86_64` | `x86_64` | Intel/AMD 64-bit |
| Other | `x86_64` | Fallback to x86_64 |

**Architecture selection:**

- VM architecture matches host architecture by default
- This ensures optimal performance (no emulation overhead)
- For cross-architecture development, see [Rosetta Configuration](#rosetta-configuration)

## Image Selection

Ubuntu 24.04 LTS cloud images are selected based on architecture:

```rust
fn get_ubuntu_image_url(arch: &str) -> String {
    match arch {
        "aarch64" => "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img",
        "x86_64" => "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img",
        _ => "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img",
    }
}
```

**Image URLs:**

- **ARM64**: `ubuntu-24.04-server-cloudimg-arm64.img`
- **x86_64**: `ubuntu-24.04-server-cloudimg-amd64.img`

**Image format:**

- Cloud images are in raw disk format
- Lima converts them to QCOW2 format for use with QEMU
- VZ uses the raw format directly

## Mount Type Selection

The `detect_mount_type()` function selects the appropriate mount type:

```rust
fn detect_mount_type(vm_type: &str) -> Option<&'static str> {
    if vm_type == "vz" && std::env::consts::OS == "macos" {
        Some("virtiofs")
    } else {
        None // Let Lima use defaults
    }
}
```

### Mount Type Selection

| VM Type | Host OS | Mount Type | Notes |
|---------|---------|------------|-------|
| `vz` | macOS | `virtiofs` | Requires macOS 13+, best performance |
| `qemu` | Linux | `9p` (default) | Lima's default for QEMU |
| `wsl2` | Windows | Default | Lima's default for WSL2 |

**virtiofs (macOS VZ):**

- **Performance**: Best performance for file system operations
- **Features**: Supports `mountInotify` for file watching
- **Requirements**: macOS 13+ (same as VZ requirement)

**9p (Linux QEMU):**

- **Performance**: Good performance, widely supported
- **Features**: Standard Linux file system protocol
- **Limitations**: No inotify support (experimental `mountInotify` available)

**Mount inotify:**

When using `virtiofs`, `mountInotify` is automatically enabled:

```rust
let mount_inotify = mount_type.map(|_| true);
```

This enables file watching for development tools that rely on inotify.

## Rosetta Configuration

Rosetta is enabled automatically on macOS ARM (Apple Silicon) when using VZ:

```rust
fn should_enable_rosetta(vm_type: &str) -> bool {
    vm_type == "vz" && std::env::consts::OS == "macos" && detect_arch() == "aarch64"
}
```

### Rosetta Settings

**When enabled:**

- Host: macOS ARM (Apple Silicon)
- VM type: `vz`
- Architecture: `aarch64`

**Configuration:**

```yaml
rosetta:
  enabled: true
  binfmt: true  # Register rosetta to /proc/sys/fs/binfmt_misc for container support
```

**Benefits:**

- **Intel-on-ARM emulation**: Run x86_64 binaries inside ARM64 VM
- **Container support**: `binfmt` enables Docker/containerd to run x86_64 containers
- **Performance**: Fast emulation via Rosetta 2

**Use cases:**

- Running x86_64-only tools or containers
- Testing cross-architecture compatibility
- Using tools that don't have ARM64 builds

## Resource Allocation

Default resource allocation is defined as constants in [`src/lima.rs`](../src/lima.rs):

```rust
pub const MEMORY: &str = "6GiB";
pub const CPUS: u32 = 4;
pub const DISK: &str = "80GiB";
```

### Resource Defaults

| Resource | Default | Notes |
|----------|---------|-------|
| **CPU** | 4 cores | Good balance for development workloads |
| **Memory** | 6 GiB | Sufficient for most development tasks |
| **Disk** | 80 GiB | QCOW2 format, grows as needed |

**Resource considerations:**

- **CPU**: Can be adjusted based on host capabilities
- **Memory**: Should leave enough for host OS and other applications
- **Disk**: QCOW2 format means disk space is allocated on-demand

**Customization:**

To change resource allocation, modify the constants in [`src/lima.rs`](../src/lima.rs) and rebuild:

```rust
pub const MEMORY: &str = "8GiB";  // Increase memory
pub const CPUS: u32 = 8;           // Increase CPU cores
pub const DISK: &str = "100GiB";   // Increase disk size
```

## SSH Configuration

SSH is configured with auto-assigned ports and agent forwarding:

```yaml
ssh:
  localPort: 0  # Auto-assign port
  loadDotSSHPubKeys: true  # Load ~/.ssh/*.pub keys
  forwardAgent: true  # Forward SSH agent for git operations
```

**SSH features:**

- **Auto-assigned ports**: Each instance gets a unique local port
- **Public key loading**: Automatically loads `~/.ssh/*.pub` keys
- **Agent forwarding**: Enables git operations with SSH keys

**Finding SSH port:**

```bash
limactl list --format '{{ .SSHLocalPort }}' <instance-name>
```

## Guest Agent

Guest agent is enabled for MCP (Model Context Protocol) support:

```yaml
guestAgent:
  enabled: true
  logPath: /var/log/lima-guest-agent.log
```

**Purpose:**

- **MCP tools**: Enables AI agents outside Lima to securely access files in the VM
- **Integration**: Provides better integration with external tools

**MCP tools available:**

- `glob`: Find files matching glob patterns
- `list_directory`: List directory contents
- `read_file`: Read file contents
- `write_file`: Write content to files
- `run_shell_command`: Execute shell commands
- `search_file_content`: Search for content in files

For more details, see the [Lima MCP Tools Documentation](https://lima-vm.io/docs/config/ai/outside/mcp/).

## Environment Variables

Default environment variables:

```yaml
env:
  LIMA_WORKDIR_DISABLED: "1"
```

**Purpose:**

- **Disable default workdir**: Prevents Lima from mounting its default work directory
- **Custom mounts**: Allows `lima-devshell` to manage mounts explicitly

## Port Forwarding

Port forwarding is explicitly empty (no custom rules):

```yaml
portForwards: []
```

**Why empty:**

- Lima's default gRPC port forwarder automatically forwards localhost ports
- Services on `127.0.0.1:PORT` in the VM are accessible on `localhost:PORT` on the host
- Works for both TCP and UDP
- No explicit rules needed for standard devshell workflows

**Example:**

If a service runs on `127.0.0.1:3000` in the VM, it's automatically accessible on `localhost:3000` on the host.

## Integration with Lima Drivers

`lima-devshell` uses Lima's built-in drivers, not custom drivers:

- **No driver development**: All VM drivers are provided by Lima
- **Configuration only**: `lima-devshell` only configures which driver to use
- **Lima compatibility**: Works with all Lima-supported VM types

**Driver selection:**

The driver is selected automatically based on host platform, ensuring optimal performance and compatibility.

## See Also

- [Lima VM Types Documentation](https://lima-vm.io/docs/config/vm-types/) - Official Lima VM type documentation
- [Lima Virtual Machine Drivers](https://lima-vm.io/docs/dev/drivers/) - Lima driver development guide
- [`src/lima.rs`](../src/lima.rs) - VM configuration implementation
- [`lima-devshell-template.yaml`](../../lima-devshell-template.yaml) - Base template configuration

