# lima-devshell

Bootstrap devshell for Lima VM environments and Home Manager configuration for macOS. This flake provides:
- Minimal tooling needed to launch project devshells inside Lima VMs
- Complete Home Manager configuration for macOS (integrated with Determinate Systems)

## Purpose

This flake serves two purposes:
1. **Bootstrap devshell**: Provides minimal tooling (nix, git, curl, etc.) to run `nix develop` on project devshells inside the Lima VM
2. **Home Manager config**: Manages your macOS home environment with packages, shell configuration, and tools

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

### From macOS

#### Option 1: As a Lima CLI Plugin (Recommended)

Install the plugin wrapper to use `lima-devshell` as a Lima plugin:

```bash
# Quick install using the installation script
./install-plugin.sh

# Or manually create a symlink
ln -s /path/to/lima-devshell/limactl-devshell /usr/local/bin/limactl-devshell

# Then use it as a Lima plugin
cd ~/.local/state/git/worktrees/io.github/pushd/percy/COMMERCE-4873
limactl devshell  # Automatically enters Lima and runs nix develop
```

The plugin will appear in `limactl --help` under "Available Plugins (Experimental)".

**Verify installation:**
```bash
limactl --help | grep devshell
limactl devshell --help
```

#### Option 2: Direct Command

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

## Home Manager Configuration (macOS)

This flake includes a complete Home Manager configuration for macOS, designed to work with [Determinate Systems Nix Installer](https://determinate.systems/nix-installer).

### Prerequisites

1. **Install Nix with Determinate Systems installer**:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **Install Home Manager** (if not already installed):
   ```bash
   nix run home-manager/master -- init --switch
   ```

### Activating the Configuration

From this repository directory:

```bash
# Switch to the Home Manager configuration
home-manager switch --flake .#bobby@macos
```

Or using the flake directly:

```bash
# Build and switch in one command
nix run home-manager/master -- switch --flake .#bobby@macos
```

### What's Configured

- **Packages**: nodejs, act, gnused, lima, yarn
- **Git**: Full git with SSH signing via 1Password
- **GitHub CLI**: Configured with SSH protocol
- **direnv**: With nix-direnv support
- **zsh**: With completion and `lima-devshell` function
- **devcontainers-cli**: For VS Code devcontainers
- **Environment**: PATH configured for Determinate Systems setup

### Updating the Configuration

After making changes to `flake.nix`:

```bash
# Rebuild and switch
home-manager switch --flake .#bobby@macos
```

### Using from a Different Location

If you want to use this flake from elsewhere (e.g., as a remote flake):

```bash
# From any directory
home-manager switch --flake github:bdelanghe/lima-devshell#bobby@macos
```

Or if using a local path:

```bash
home-manager switch --flake /path/to/lima-devshell#bobby@macos
```

## Lima Templates

This project includes a custom Lima template (`lima-devshell-template.yaml`) optimized for Nix devshell development. The `lima-devshell` tool dynamically generates instance-specific YAML configurations based on this template.

### Using the Custom Template

The template can be used directly with `limactl`:

```bash
# Create an instance from the template
limactl create --name=my-dev lima-devshell-template.yaml

# Start the instance
limactl start my-dev
```

However, the `lima-devshell` command automatically generates and uses customized configurations, so manual template usage is typically not needed.

### Exploring Existing Lima Templates

Lima provides many pre-built templates for different distributions and use cases. You can explore them:

1. **View available templates**: See the [Lima Templates Documentation](https://lima-vm.io/docs/templates/)

2. **Copy an existing template locally**:
   ```bash
   # Copy the default template
   limactl template copy default /tmp/default-template.yaml
   
   # Copy a specific template (e.g., fedora, docker, k8s)
   limactl template copy template://fedora /tmp/fedora-template.yaml
   ```

3. **Use a template directly**:
   ```bash
   # Create instance from built-in template
   limactl start template://fedora
   limactl start template://docker
   limactl start template://k8s
   ```

4. **Validate a template**:
   ```bash
   limactl template validate lima-devshell-template.yaml
   ```

### Template Customization

The `lima-devshell-template.yaml` file serves as the base configuration. The Rust code in `src/lima.rs` customizes it per instance by:
- Adding dynamic mounts for worktrees and bare repos
- Setting instance-specific paths
- Configuring resource allocation (CPU, memory, disk)

To modify the base template, edit `lima-devshell-template.yaml` and update the constants in `src/lima.rs` accordingly.

### JSON Schema

This project includes a comprehensive JSON schema (`lima-config-schema.json`) based on the [Lima default template](https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/default.yaml). The schema can be used for:

- **Validation**: Validate Lima YAML configuration files
- **Documentation**: Understand all available configuration options
- **IDE Support**: Enable autocomplete and validation in editors that support JSON Schema

The schema covers all major Lima configuration fields including:
- VM type and architecture settings
- Image and resource configuration
- Mount and network settings
- SSH and port forwarding
- Provisioning scripts
- Environment variables
- And many more advanced options

You can use the schema with tools like:
- [ajv-cli](https://github.com/ajv-validator/ajv-cli) for command-line validation
- VS Code with JSON Schema support
- Online validators like [jsonschemavalidator.net](https://www.jsonschemavalidator.net/)

## SSH Access

All Lima instances created by `lima-devshell` support SSH access, which is useful for:
- **VS Code Remote Development**: Connect directly via SSH
- **Direct terminal access**: Use `ssh` instead of `limactl shell`
- **CI/CD integration**: Tools that expect SSH connectivity
- **Git operations**: SSH agent forwarding is enabled for seamless git operations

### SSH Configuration

SSH is automatically configured with:
- **Auto-assigned ports**: Each instance gets a unique local port (check with `limactl list`)
- **Public key authentication**: Your `~/.ssh/*.pub` keys are automatically loaded
- **SSH agent forwarding**: Enabled for git operations and key-based authentication

### Using SSH

#### Option 1: Direct SSH with config file

Lima generates SSH config files for each instance. You can use them directly:

```bash
# Find the SSH config file for an instance
limactl list --format='{{.SSHConfigFile}}' <instance-name>

# Connect using the config file
ssh -F ~/.lima/<instance-name>/ssh.config lima-<instance-name>
```

#### Option 2: Add to your SSH config (Recommended)

Add this line to your `~/.ssh/config` to automatically include all Lima instances:

```
Include ~/.lima/*/ssh.config
```

Then you can connect directly:

```bash
ssh lima-<instance-name>
```

This is especially useful for **VS Code Remote Development**, which can automatically discover and connect to Lima instances.

#### Option 3: Direct connection without config

If your SSH client doesn't support config files:

```bash
# Get the port number
limactl list --format '{{ .SSHLocalPort }}' <instance-name>

# Connect directly
ssh -p <PORT> -i ~/.lima/_config/user -o NoHostAuthenticationForLocalhost=yes 127.0.0.1
```

### VS Code Remote Development

VS Code Remote Development with Lima provides a secure development environment by running VS Code extensions (including AI agents like GitHub Copilot) inside the VM, preventing them from directly executing untrusted commands on your host machine.

#### Setup Steps

1. **Add SSH config include** (one-time setup):
   
   Add this line to your `~/.ssh/config`:
   ```
   Include ~/.lima/*/ssh.config
   ```

2. **Install VS Code extensions** (if not already installed):
   - **Remote Explorer** (for discovering Lima instances)
   - **Remote - SSH** (for SSH-based remote development)

3. **Connect to your Lima instance**:
   - Open the **Remote Explorer** in the VS Code sidebar
   - Select `lima-<instance-name>` from the SSH remote list
   - VS Code will connect and install the remote server components

4. **Open your workspace**:
   - Once connected, use **File > Open Folder**
   - Navigate to your mounted worktree at `/worktrees/io.github/.../...`
   - Or use **File > Clone Git Repository** to clone a new repository

#### Security Benefits

Running VS Code in Lima provides security benefits:
- **AI agent isolation**: Extensions like GitHub Copilot run inside the VM, not on your host
- **Sandboxed execution**: Untrusted code execution is contained within the VM
- **File access control**: Only mounted directories are accessible to VS Code

#### Optional: Enhanced Security with `--mount-none`

For maximum security (especially with AI agents), you can start instances with `--mount-none` to prevent access to host files. However, this conflicts with `lima-devshell`'s mount-based workflow, so it's only recommended if you're manually managing instances and copying files with `limactl cp`.

For `lima-devshell` workflows, the default mount configuration provides a good balance of security and functionality.

For more details, see the [Lima VS Code Documentation](https://lima-vm.io/docs/examples/vscode/).

## MCP (Model Context Protocol) Support

This project is configured to support MCP (Model Context Protocol) tools, which allow AI agents running outside Lima to securely read, write, and execute files within the VM sandbox.

### What is MCP?

Lima implements the "MCP Sandbox Interface" that provides MCP tools for:
- **`glob`**: Find files matching glob patterns
- **`list_directory`**: List directory contents
- **`read_file`**: Read file contents
- **`write_file`**: Write content to files
- **`run_shell_command`**: Execute shell commands
- **`search_file_content`**: Search for content in files using regex

These tools are more secure and efficient than default AI agent tools because they operate within Lima's sandboxed environment.

### Configuration

MCP support is automatically enabled when:
1. **Guest agent is enabled** (configured by default in all instances)
2. **Lima instance is running** (MCP tools are exposed through Lima's host agent)

The guest agent is enabled in both the template (`lima-devshell-template.yaml`) and all dynamically generated configurations.

### Using MCP Tools

To use MCP tools with your Lima instances:

1. **Ensure your Lima instance is running**:
   ```bash
   limactl start <instance-name>
   ```

2. **Configure your MCP-compatible AI agent** to connect to Lima's MCP server. The exact configuration depends on your AI agent, but typically involves:
   - Specifying Lima as an MCP server
   - Providing the instance name or connection details
   - Configuring the root directory for file operations

3. **Use the MCP tools** through your AI agent. The tools will operate within the VM's sandbox, providing secure file access and command execution.

For more details, see the [Lima MCP Tools Documentation](https://lima-vm.io/docs/config/ai/outside/mcp/).

## Lima CLI Plugin Support

This project includes a Lima CLI plugin wrapper (`limactl-devshell`) that allows `lima-devshell` to be used as a native Lima plugin. This is the **recommended long-term approach** for better integration with Lima's ecosystem.

⚠️ **Requirement**: CLI plugins require **Lima >= 2.0.0**. Check your version with `limactl --version`. If you're using an older version, you can:
- Continue using `lima-devshell` directly (works with all Lima versions)
- Upgrade Lima to 2.0.0+ to use the plugin system

### Plugin Features

- **Automatic Discovery**: Appears in `limactl --help` under "Available Plugins"
- **Native Integration**: Works seamlessly with Lima's plugin system
- **Consistent Interface**: Uses `limactl devshell` instead of a separate command
- **Description Support**: Plugin description is shown in help output

### Installation as Plugin

#### Quick Install (Recommended)

Use the provided installation script:

```bash
# From the project root
./install-plugin.sh

# Or specify a custom installation directory
INSTALL_DIR=~/.local/bin ./install-plugin.sh
```

#### Manual Installation

```bash
# Create symlink to plugin wrapper
ln -s /path/to/lima-devshell/limactl-devshell /usr/local/bin/limactl-devshell

# Verify it works
limactl --help  # Should show "devshell" in Available Plugins section
limactl devshell --help  # Should show lima-devshell help
```

#### Via Home Manager (Future)

The Home Manager configuration can be updated to install the plugin wrapper automatically. This will be added in a future update.

### Migration Path

**Current State**: `lima-devshell` works as a standalone command  
**Future State**: `limactl devshell` will be the primary interface

Both interfaces will continue to work during the transition period. The plugin approach provides:
- Better discoverability (`limactl --help` shows all plugins)
- Consistent naming with other Lima commands
- Integration with Lima's plugin ecosystem

For more details on Lima plugins, see the [Lima CLI Plugins Documentation](https://lima-vm.io/docs/config/plugin/cli/).

## Lima Feature Status

This section documents Lima's deprecated and experimental features to help users understand feature stability and migration paths. For the most up-to-date information, refer to the [official Lima documentation](https://lima-vm.io/docs/releases/).

### Deprecated Features

Lima maintains a list of deprecated features that should be avoided in new configurations. This project avoids using deprecated features.

**Official Documentation**: [Lima Deprecated Features](https://lima-vm.io/docs/releases/deprecated/)

Key deprecated features to be aware of:

- **`limactl show-ssh` command**: Deprecated in v0.18.0. Use `ssh -F ~/.lima/default/ssh.config lima-default` instead.
- **`limactl --yes` flag**: Deprecated in v2.0.0. Use `limactl (clone|rename|edit|shell) --start` instead.
- **Environment variable `LIMA_SSH_OVER_VSOCK`**: Deprecated in v2.0.2. Use the YAML property `.ssh.overVsock` instead.

**Note**: While `LIMA_SSH_OVER_VSOCK` appears in the environment variables schema (`lima-env-vars-schema.json`), this project does not use it. Use `.ssh.overVsock` in the YAML configuration instead.

### Experimental Features

⚠️ **Warning**: Experimental features are subject to change and may be modified or removed in future Lima releases. Use them with caution and check the [official experimental features documentation](https://lima-vm.io/docs/releases/experimental/) for updates.

**Official Documentation**: [Lima Experimental Features](https://lima-vm.io/docs/releases/experimental/)

Experimental features used or referenced by this project:

- **⚠️ CLI Plugins (Experimental)**: The `limactl devshell` plugin wrapper uses Lima's experimental CLI plugin system. This appears in `limactl --help` under "Available Plugins (Experimental)". The plugin interface may change in future Lima releases.

- **⚠️ `limactl template *` commands (Experimental)**: The template commands (`template copy`, `template url`, `template validate`, `template yq`) are experimental. This project's documentation references these commands for exploring and validating Lima templates, but they may change in future releases.

- **⚠️ `vmType: wsl2` (Experimental)**: The `wsl2` VM type is experimental. This project's code references it for Windows support, but it's not actively used on macOS/Linux hosts where this project primarily operates.

Other experimental features (not used by this project):

- `mountType: virtiofs` on Linux
- `arch`: `riscv64`, `armv7l`, `s390x`, and `ppc64le`
- `video.display: vnc` and relevant configuration
- `audio.device`
- `mountInotify: true`
- External drivers (building and using drivers as separate executables)
- `vmType: krunkit`
- `github:` URL scheme for referencing templates
- `limactl snapshot *` commands
- `limactl tunnel` command
- `limactl mcp *` commands

### Stable Features (Graduated from Experimental)

The following features were once experimental but are now stable:

- **`vmType: vz`**: Now stable. This project uses `vz` on macOS for optimal performance.
- **`mountType: virtiofs`**: Now stable (graduated in v1.0). Not currently used by this project.
- **`vmType: vz` with `mountType: virtiofs`**: Stable combination for macOS.
- **`mode: user-v2` in networks**: Now stable (graduated in v1.0).

### Project-Specific Notes

This project uses the following Lima features:

**Stable Features**:
- `vmType: vz` (macOS) and `vmType: qemu` (Linux) - Stable VM types
- `guestAgent` - Required for MCP (Model Context Protocol) support
- SSH configuration - Standard SSH access with agent forwarding
- Standard mounts - File system mounts for worktrees and bare repos
- Rosetta support - For Intel-on-ARM emulation on macOS (when using `vz`)

**Experimental Features**:
- CLI plugins - Used for `limactl devshell` integration
- Template commands - Referenced in documentation for template exploration

**Avoided Features**:
- All deprecated features are avoided
- Experimental features are only used when necessary (CLI plugins) or for documentation purposes (template commands)

When in doubt, prefer stable features. Experimental features may change, so check the [Lima experimental features documentation](https://lima-vm.io/docs/releases/experimental/) before relying on them in production workflows.

## Lima Subprojects

Lima has several subprojects that extend its functionality or provide related tools. These are maintained by the Lima project team.

**Official Documentation**: [Lima Subprojects](https://lima-vm.io/docs/community/subprojects/)

Key subprojects:

- **[socket_vmnet](https://github.com/lima-vm/socket_vmnet)**: vmnet.framework support for unmodified rootless QEMU. Provides network support for Lima VMs on macOS.

- **[lima-actions](https://github.com/lima-vm/lima-actions)**: Run Lima on GitHub Actions. Enables using Lima VMs in CI/CD pipelines.

- **[go-qcow2reader](https://github.com/lima-vm/go-qcow2reader)**: qcow2 reader for Go. Utility library for working with QEMU disk images.

- **[sshocker](https://github.com/lima-vm/sshocker)**: ssh + reverse sshfs + port forwarder, in Docker-like CLI. This was the predecessor of Lima and is now maintained as a separate project.

- **[alpine-lima](https://github.com/lima-vm/alpine-lima)**: Create an Alpine-based image for Lima. Provides lightweight Alpine Linux images optimized for Lima.

For a complete list of Lima-related projects, see the [lima-vm GitHub organization](https://github.com/lima-vm).

## Repository Structure

- **Bare repo**: `~/.local/share/git/bare/io.github/bdelanghe/lima-devshell.git/`
- **Worktree**: `~/.local/state/git/worktrees/io.github/bdelanghe/lima-devshell/`

Follows the same XDG-based git worktree pattern as other repos.

