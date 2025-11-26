# Testing

This document describes the testing approach and practices for `lima-devshell`.

## Overview

`lima-devshell` includes unit tests for core functionality, particularly VM configuration generation. The tests validate that the plugin correctly detects platform characteristics and generates valid Lima YAML configurations.

## Unit Tests

Unit tests are located in [`src/lima.rs`](../src/lima.rs) and test the following areas:

### VM Type Detection

Tests validate that `detect_vm_type()` correctly identifies the VM type based on the host OS:

```rust
#[test]
fn test_detect_vm_type() {
    let vm_type = detect_vm_type();
    
    // Verify we get a valid VM type (not empty)
    assert!(!vm_type.is_empty(), "VM type should not be empty");
    
    // Verify platform-specific detection
    match std::env::consts::OS {
        "macos" => assert_eq!(vm_type, "vz", "macOS should use vz VM type"),
        "linux" => assert_eq!(vm_type, "qemu", "Linux should use qemu VM type"),
        "windows" => assert_eq!(vm_type, "wsl2", "Windows should use wsl2 VM type"),
        _ => assert_eq!(vm_type, "qemu", "Unknown platform should fallback to qemu"),
    }
}
```

**What it tests:**

- VM type is not empty
- Platform-specific detection (macOS → `vz`, Linux → `qemu`, Windows → `wsl2`)
- Fallback behavior for unknown platforms

### Architecture Detection

Tests validate that `detect_arch()` correctly maps host architecture:

```rust
#[test]
fn test_detect_arch() {
    let arch = detect_arch();
    
    // Verify we get a valid architecture (not empty)
    assert!(!arch.is_empty(), "Architecture should not be empty");
    
    // Verify architecture mapping
    match std::env::consts::ARCH {
        "aarch64" | "arm64" => assert_eq!(arch, "aarch64", "ARM64 should map to aarch64"),
        "x86_64" => assert_eq!(arch, "x86_64", "x86_64 should map to x86_64"),
        _ => assert_eq!(arch, "x86_64", "Unknown architecture should fallback to x86_64"),
    }
}
```

**What it tests:**

- Architecture is not empty
- Correct mapping (ARM64 → `aarch64`, x86_64 → `x86_64`)
- Fallback behavior for unknown architectures

### Rosetta Detection

Tests validate that Rosetta is only enabled on macOS ARM with VZ:

```rust
#[test]
fn test_rosetta_detection() {
    let vm_type = detect_vm_type();
    let should_enable = should_enable_rosetta(vm_type);
    let os = std::env::consts::OS;
    let arch = detect_arch();
    
    // Rosetta should only be enabled on macOS ARM with VZ
    if os == "macos" && arch == "aarch64" && vm_type == "vz" {
        assert!(should_enable, "Rosetta should be enabled on macOS ARM with VZ");
    } else {
        assert!(!should_enable, "Rosetta should not be enabled on other platforms");
    }
}
```

**What it tests:**

- Rosetta is enabled only on macOS ARM with VZ
- Rosetta is disabled on other platforms

### Mount Type Detection

Tests validate that mount type is correctly selected:

```rust
#[test]
fn test_detect_mount_type() {
    let vm_type = detect_vm_type();
    let mount_type = detect_mount_type(vm_type);
    let os = std::env::consts::OS;
    
    // virtiofs should be detected for macOS with VZ
    if os == "macos" && vm_type == "vz" {
        assert_eq!(mount_type, Some("virtiofs"), "virtiofs should be detected for macOS with VZ");
    } else {
        assert_eq!(mount_type, None, "mount type should be None for other configurations");
    }
}
```

**What it tests:**

- `virtiofs` is selected for macOS with VZ
- Default (None) is used for other configurations

### YAML Generation

Tests validate that generated YAML is correct and valid:

```rust
#[test]
fn test_generate_lima_yaml_structure() {
    let instance = create_test_instance();
    let yaml = generate_lima_yaml(&instance).expect("should generate YAML");
    
    // Verify YAML contains expected fields
    assert!(yaml.contains("vmType:"));
    assert!(yaml.contains("arch:"));
    assert!(yaml.contains("memory: 6GiB"));
    assert!(yaml.contains("cpus: 4"));
    assert!(yaml.contains("disk: 80GiB"));
}
```

**What it tests:**

- YAML contains required fields
- Resource allocation values are correct
- YAML structure is valid

### YAML Validity

Tests validate that generated YAML can be parsed:

```rust
#[test]
fn test_generate_lima_yaml_valid_yaml() {
    let instance = create_test_instance();
    let yaml = generate_lima_yaml(&instance).expect("should generate YAML");
    
    // Verify it's valid YAML by parsing it
    let parsed: Result<LimaConfig, _> = serde_yaml::from_str(&yaml);
    assert!(parsed.is_ok(), "Generated YAML should be valid");
    
    let config = parsed.unwrap();
    // Verify configuration matches expected values
    assert_eq!(config.memory.as_deref(), Some("6GiB"));
    assert_eq!(config.cpus, Some(4));
}
```

**What it tests:**

- Generated YAML is valid and parseable
- Parsed configuration matches expected values

### Mount Configuration

Tests validate that mounts are correctly configured:

```rust
#[test]
fn test_generate_lima_yaml_mounts() {
    let instance = create_test_instance();
    let yaml = generate_lima_yaml(&instance).expect("should generate YAML");
    
    // Verify mounts are present
    assert!(yaml.contains("/Users/test/worktree"));
    assert!(yaml.contains("/worktrees/test/repo"));
    assert!(yaml.contains("writable: true"));
}
```

**What it tests:**

- Worktree and bare repo mounts are present
- Mount points are correctly set
- Mounts are writable

## Running Tests

### Run All Tests

```bash
cargo test
```

### Run Specific Test

```bash
cargo test test_detect_vm_type
```

### Run Tests with Output

```bash
cargo test -- --nocapture
```

### Run Tests for Specific Module

```bash
cargo test --lib lima::tests
```

## Test Structure

### Test Helper Functions

The test module includes helper functions:

```rust
fn create_test_instance() -> InstanceModel {
    InstanceModel {
        name: "test-instance".to_string(),
        worktree_mount_host: PathBuf::from("/Users/test/worktree"),
        worktree_mount_guest: "/worktrees/test/repo".to_string(),
        bare_repo_mount_host: PathBuf::from("/Users/test/bare.git"),
        bare_repo_mount_guest: "/git/bare/worktrees".to_string(),
        repo_name: "test-repo".to_string(),
    }
}
```

**Purpose:**

- Creates test instances with known values
- Ensures consistent test data across tests

## Manual Testing

### End-to-End Testing

To test the plugin end-to-end:

1. **Set up test worktree:**

```bash
# Create a test worktree
mkdir -p ~/.local/state/git/worktrees/test/owner/repo
cd ~/.local/state/git/worktrees/test/owner/repo

# Create a minimal flake.nix
cat > flake.nix <<EOF
{
  outputs = { self, nixpkgs }: {
    devShells.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      packages = [ nixpkgs.legacyPackages.x86_64-linux.hello ];
    };
  };
}
EOF
```

2. **Run lima-devshell:**

```bash
lima-devshell
```

3. **Verify:**

- Instance is created in `~/.lima/test-owner-repo/`
- Instance starts successfully
- Devshell launches inside the VM
- Files are accessible at `/worktrees/test/owner/repo`

### Testing Instance Management

**Test instance creation:**

```bash
# Create instance
lima-devshell

# Verify instance exists
limactl list

# Check instance status
limactl list --format '{{ .Name }}: {{ .Status }}' test-owner-repo
```

**Test instance cleanup:**

```bash
# Stop instance
limactl stop test-owner-repo

# Delete instance
limactl delete test-owner-repo

# Verify deletion
limactl list | grep test-owner-repo
```

### Testing Path Mapping

**Test host-to-guest mapping:**

1. Create a file in the worktree on the host
2. Enter the Lima instance
3. Verify the file is accessible at the mapped guest path

```bash
# On host
echo "test" > ~/.local/state/git/worktrees/test/owner/repo/test.txt

# In Lima VM
limactl shell test-owner-repo
cat /worktrees/test/owner/repo/test.txt  # Should show "test"
```

### Testing Git Integration

**Test bare repository mounting:**

1. Create a bare repository
2. Create a worktree from it
3. Verify the bare repo is mounted in the VM

```bash
# Create bare repo
git init --bare ~/.local/share/git/bare/test/repo.git

# Create worktree
git -C ~/.local/share/git/bare/test/repo.git worktree add ~/.local/state/git/worktrees/test/owner/repo

# Run lima-devshell
cd ~/.local/state/git/worktrees/test/owner/repo
lima-devshell

# In VM, verify bare repo is mounted
limactl shell test-owner-repo
ls /git/bare/repo.git  # Should show bare repo contents
```

## Test Data

### Example Worktree Paths

Common worktree path patterns:

```
~/.local/state/git/worktrees/io.github/owner/repo/worktree
~/.local/state/git/worktrees/io.github/owner/repo
~/.local/state/git/worktrees/io.github/owner
```

### Expected Instance Names

Instance names derived from paths:

| Path Segments | Instance Name |
|---------------|---------------|
| `io.github/owner/repo/worktree` | `owner-repo-worktree` |
| `io.github/owner/repo` | `owner-repo` |
| `io.github/owner` | `owner` |

## CI/CD Considerations

### Testing in CI

For CI/CD environments:

1. **Lima installation**: Ensure Lima is installed in the CI environment
2. **VM support**: Ensure the CI environment supports virtualization (QEMU/KVM for Linux)
3. **Test isolation**: Each test should use a unique instance name
4. **Cleanup**: Always clean up test instances after tests

**Example CI test script:**

```bash
#!/bin/bash
set -e

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

# Run lima-devshell (non-interactive)
lima-devshell || true

# Cleanup
limactl delete --force test-owner-repo || true
```

### GitHub Actions

For GitHub Actions, use Lima's official action:

```yaml
- uses: lima-vm/lima-actions/setup-lima@v1
- run: cargo test
```

## Test Coverage

Current test coverage:

- ✅ VM type detection
- ✅ Architecture detection
- ✅ Rosetta detection
- ✅ Mount type detection
- ✅ YAML generation
- ✅ YAML validity
- ✅ Mount configuration
- ✅ SSH configuration
- ✅ Environment variables
- ✅ Guest agent configuration

**Areas for future testing:**

- Instance lifecycle (create, start, stop, delete)
- Path mapping edge cases
- Git worktree discovery edge cases
- Error handling scenarios

## See Also

- [`src/lima.rs`](../src/lima.rs) - Test implementations
- [Lima Testing Documentation](https://lima-vm.io/docs/dev/testing/) - Official Lima testing guide
- [Rust Testing Guide](https://doc.rust-lang.org/book/ch11-00-testing.html) - Rust testing documentation

