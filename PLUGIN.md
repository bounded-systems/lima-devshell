# Lima CLI Plugin Migration

This document outlines the plan to migrate `lima-devshell` to a native Lima CLI plugin.

⚠️ **Important**: CLI plugins require **Lima >= 2.0.0**. If you're using an older version of Lima, you'll need to upgrade first.

## Current State

- `lima-devshell` works as a standalone Rust binary
- Installed via Home Manager as a shell function
- Works independently of Lima's plugin system

## Target State

- `limactl devshell` as the primary interface
- Discoverable via `limactl --help`
- Integrated with Lima's plugin ecosystem
- Maintains backward compatibility with `lima-devshell` command

## Implementation

### Phase 1: Plugin Wrapper (Current)

✅ Created `limactl-devshell` wrapper script that:
- Follows Lima's plugin naming convention (`limactl-<name>`)
- Includes plugin description in `<limactl-desc>` format
- Locates and executes the `lima-devshell` binary
- Can be installed manually or via package manager

**Status**: Complete - wrapper script created and documented

### Phase 2: Home Manager Integration (Planned)

- Update Home Manager configuration to install `limactl-devshell` symlink
- Ensure plugin is in PATH for Lima to discover
- Update shell configuration to prefer `limactl devshell` over `lima-devshell`

### Phase 3: Binary Rename (Optional)

Consider renaming the binary from `lima-devshell` to `limactl-devshell` directly:
- Pros: Simpler, no wrapper needed
- Cons: Breaking change, requires updating all references

**Decision**: Keep wrapper approach for backward compatibility

### Phase 4: Documentation Updates

- Update all examples to use `limactl devshell`
- Mark `lima-devshell` as legacy/deprecated (with long deprecation period)
- Update CI/CD and automation scripts

## Installation

### Manual Installation

```bash
# Install plugin wrapper
ln -s /path/to/lima-devshell/limactl-devshell /usr/local/bin/limactl-devshell

# Verify
limactl --help | grep devshell
limactl devshell --help
```

### Via Package Manager (Future)

The plugin wrapper will be installed automatically via Home Manager configuration.

## Benefits

1. **Discoverability**: Plugin appears in `limactl --help`
2. **Consistency**: Follows Lima's command structure (`limactl <subcommand>`)
3. **Integration**: Works with Lima's plugin ecosystem
4. **Future-proof**: Aligns with Lima's plugin architecture

## References

- [Lima CLI Plugins Documentation](https://lima-vm.io/docs/config/plugin/cli/)
- [Plugin Discovery](https://lima-vm.io/docs/config/plugin/cli/#plugin-discovery)
- [Plugin Descriptions](https://lima-vm.io/docs/config/plugin/cli/#plugin-descriptions)

