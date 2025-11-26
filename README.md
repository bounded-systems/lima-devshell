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

## Repository Structure

- **Bare repo**: `~/.local/share/git/bare/io.github/bdelanghe/lima-devshell.git/`
- **Worktree**: `~/.local/state/git/worktrees/io.github/bdelanghe/lima-devshell/`

Follows the same XDG-based git worktree pattern as other repos.

