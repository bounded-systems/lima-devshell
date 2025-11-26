# limactl-devshell Plugin Reference

This document describes the `limactl-devshell` plugin wrapper for Lima CLI integration.

## Synopsis

```bash
limactl devshell [OPTIONS]
```

## Description

`limactl-devshell` is a Lima CLI plugin wrapper that allows `lima-devshell` to be used as a native Lima plugin. This provides better integration with Lima's ecosystem and makes the plugin discoverable via `limactl --help`.

The plugin wrapper:

1. Locates the `lima-devshell` binary
2. Executes it with the provided arguments
3. Provides plugin metadata for Lima's plugin system

## Installation

### Quick Install (Recommended)

Use the provided installation script:

```bash
# From the project root
./install-plugin.sh

# Or specify a custom installation directory
INSTALL_DIR=~/.local/bin ./install-plugin.sh
```

### Manual Installation

Create a symlink to the plugin wrapper:

```bash
ln -s /path/to/lima-devshell/limactl-devshell /usr/local/bin/limactl-devshell
```

**Installation paths:**

The plugin wrapper searches for `lima-devshell` in:

1. Same directory as the wrapper script (for development)
2. Standard installation paths: `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`
3. PATH

### Via Home Manager (Future)

The Home Manager configuration can be updated to install the plugin wrapper automatically. This will be added in a future update.

## Requirements

### Lima Version

**Required:** Lima >= 2.0.0

CLI plugins are not available in older versions of Lima. The plugin wrapper checks the Lima version and exits with an error if an older version is detected.

**Check Lima version:**

```bash
limactl --version
```

**Upgrade Lima:**

- **macOS:** `brew upgrade lima`
- **Linux:** Follow [Lima installation instructions](https://lima-vm.io/docs/installation/)

## Usage

### As Lima Plugin

Once installed, use it as a Lima plugin:

```bash
limactl devshell
```

The plugin appears in `limactl --help` under "Available Plugins (Experimental)":

```
Available Plugins (Experimental):
  devshell  Enter Lima dev environment from a valid Git worktree. Automatically manages Lima instances for Nix devshell development.
```

### Plugin Discovery

Lima automatically discovers plugins named `limactl-<name>` in your PATH. The plugin description is extracted from the `<limactl-desc>` comment in the wrapper script.

### Help

Get help for the plugin:

```bash
limactl devshell --help
```

This shows the `lima-devshell` help output.

## Options

All options are passed through to the underlying `lima-devshell` binary. See [`lima-devshell`](./lima-devshell.md) for available options.

### `-d, --directory <DIRECTORY>`

Specify the target directory.

**Example:**

```bash
limactl devshell --directory ~/.local/state/git/worktrees/io.github/owner/repo/main
```

## Exit Codes

The plugin wrapper passes through exit codes from `lima-devshell`:

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Error (validation failure, Lima operation failure, etc.) |
| `1` | Plugin wrapper error (binary not found, Lima version too old, etc.) |

## Examples

### Basic Usage

Enter a devshell from the current directory:

```bash
cd ~/.local/state/git/worktrees/io.github/owner/repo/main
limactl devshell
```

### Specify Directory

Enter a devshell from a specific directory:

```bash
limactl devshell --directory ~/.local/state/git/worktrees/io.github/owner/repo/main
```

### Verify Installation

Check that the plugin is installed and discoverable:

```bash
# Check plugin appears in help
limactl --help | grep devshell

# Check plugin help
limactl devshell --help
```

## Plugin Metadata

### Description

The plugin description is extracted from the `<limactl-desc>` comment in the wrapper script:

```bash
# <limactl-desc>Enter Lima dev environment from a valid Git worktree. Automatically manages Lima instances for Nix devshell development.</limactl-desc>
```

This description appears in `limactl --help` output.

### Plugin Name

The plugin name is derived from the script filename:

- Script: `limactl-devshell`
- Plugin command: `limactl devshell`

Lima automatically strips the `limactl-` prefix to get the plugin name.

## Binary Discovery

The plugin wrapper searches for the `lima-devshell` binary in the following order:

1. **Same directory as wrapper** (for development):
   ```bash
   ./limactl-devshell  # Looks for ./lima-devshell
   ```

2. **Standard installation paths**:
   - `/usr/local/bin/lima-devshell`
   - `/opt/homebrew/bin/lima-devshell`
   - `~/.local/bin/lima-devshell`

3. **PATH**:
   - Searches for `lima-devshell` in PATH

### Binary Not Found

If the binary is not found, the plugin wrapper exits with an error:

```
limactl-devshell: error: lima-devshell binary not found
limactl-devshell: please install lima-devshell or ensure it's in your PATH
```

**Solutions:**

- Install `lima-devshell` via Home Manager or manually
- Ensure `lima-devshell` is in your PATH
- Use the full path to the binary in the wrapper script

## Version Checking

The plugin wrapper checks the Lima version before executing:

```bash
# Check Lima version if limactl is available
if command -v limactl >/dev/null 2>&1; then
    LIMA_VERSION=$(limactl --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
    if [ -n "$LIMA_VERSION" ]; then
        MAJOR_VERSION=$(echo "$LIMA_VERSION" | cut -d. -f1)
        if [ "$MAJOR_VERSION" -lt 2 ]; then
            echo "limactl-devshell: error: Lima version $LIMA_VERSION detected"
            echo "limactl-devshell: CLI plugins require Lima >= 2.0.0"
            exit 1
        fi
    fi
fi
```

**Error if version too old:**

```
limactl-devshell: error: Lima version 1.9.0 detected
limactl-devshell: CLI plugins require Lima >= 2.0.0
limactl-devshell: Please upgrade Lima or use 'lima-devshell' command directly
```

## Migration Path

### Current State

- `lima-devshell` works as a standalone command
- `limactl devshell` works as a plugin (when installed)

### Future State

- `limactl devshell` will be the primary interface
- `lima-devshell` will continue to work for backward compatibility

### Benefits of Plugin Approach

1. **Discoverability**: Plugin appears in `limactl --help`
2. **Consistency**: Uses `limactl <subcommand>` pattern
3. **Integration**: Works with Lima's plugin ecosystem
4. **Future-proof**: Aligns with Lima's plugin architecture

## Troubleshooting

### Plugin Not Discovered

**Issue:** Plugin doesn't appear in `limactl --help`

**Solutions:**

- Ensure `limactl-devshell` is in your PATH
- Check file permissions: `chmod +x limactl-devshell`
- Verify Lima version: `limactl --version` (must be >= 2.0.0)
- Check plugin naming: must be `limactl-<name>`

### Binary Not Found

**Issue:** `lima-devshell binary not found`

**Solutions:**

- Install `lima-devshell` via Home Manager or manually
- Ensure `lima-devshell` is in your PATH
- Check installation paths: `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`

### Version Too Old

**Issue:** `CLI plugins require Lima >= 2.0.0`

**Solutions:**

- Upgrade Lima to version 2.0.0 or later
- Use `lima-devshell` command directly (doesn't require plugin support)

### Permission Denied

**Issue:** `Permission denied` when running plugin

**Solutions:**

- Make wrapper executable: `chmod +x limactl-devshell`
- Check installation directory permissions
- Use `sudo` if installing to system directories (not recommended)

## See Also

- [`lima-devshell`](./lima-devshell.md) - Main command reference
- [Lima CLI Plugins Documentation](https://lima-vm.io/docs/config/plugin/cli/) - Official Lima plugin documentation
- [`limactl-devshell`](../../limactl-devshell) - Plugin wrapper script
- [`install-plugin.sh`](../../install-plugin.sh) - Installation script

