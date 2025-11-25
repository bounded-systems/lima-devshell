use crate::app::{AppContext, InstanceModel};
use crate::script::build_guest_script;
use anyhow::{Context as AnyhowContext, Result};
use std::collections::hash_map::DefaultHasher;
use std::env;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::Command;

// Lima VM configuration constants
pub const VM_TYPE: &str = "vz";
pub const ARCH: &str = "aarch64";
pub const UBUNTU_IMAGE_URL: &str =
    "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img";
pub const MEMORY: &str = "6GiB";
pub const CPUS: u32 = 4;
pub const DISK: &str = "80GiB";
const SSH_PORT_BASE: u16 = 60022;

/// Compute SSH port from instance name hash to avoid collisions
pub fn compute_ssh_port(instance_name: &str) -> u16 {
    let mut hasher = DefaultHasher::new();
    instance_name.hash(&mut hasher);
    let hash = hasher.finish();
    SSH_PORT_BASE + (hash % 1000) as u16
}

/// Generate Lima YAML configuration from instance model
fn generate_lima_yaml(instance: &InstanceModel) -> String {
    let ssh_port = compute_ssh_port(&instance.name);
    format!(
        r#"# Lima instance for {} development
vmType: "{}"
arch: "{}"

images:
  - location: "{}"
    arch: "{}"

mounts:
  # Mount this specific worktree
  - location: "{}"
    mountPoint: "{}"
    writable: true
  # Mount the bare repo
  - location: "{}"
    mountPoint: "{}"
    writable: true

memory: "{}"
cpus: {}
disk: "{}"

ssh:
  localPort: {}
  loadDotSSHPubKeys: true

env:
  LIMA_WORKDIR_DISABLED: "1"

# Provisioning step to create the dev user
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
"#,
        instance.repo_name,
        VM_TYPE,
        ARCH,
        UBUNTU_IMAGE_URL,
        ARCH,
        instance.worktree_mount_host.display(),
        instance.worktree_mount_guest,
        instance.bare_repo_mount_host.display(),
        instance.bare_repo_mount_guest,
        MEMORY,
        CPUS,
        DISK,
        ssh_port
    )
}

/// Write Lima YAML configuration to a specific path
fn write_lima_yaml(instance: &InstanceModel, yaml_path: &Path) -> Result<()> {
    let yaml_content = generate_lima_yaml(instance);
    std::fs::write(yaml_path, yaml_content).context("failed to write Lima YAML configuration")?;
    Ok(())
}

/// Get Lima home directory (LIMA_HOME or default ~/.lima)
fn get_lima_home() -> Result<PathBuf> {
    if let Ok(lima_home) = env::var("LIMA_HOME") {
        Ok(PathBuf::from(lima_home))
    } else {
        let home = env::var("HOME").context("HOME environment variable not set")?;
        Ok(PathBuf::from(format!("{}/.lima", home)))
    }
}

/// Check if a Lima instance is currently running
fn is_instance_running(instance_name: &str) -> Result<bool> {
    let lima_home = get_lima_home()?;
    let lima_instance_dir = lima_home.join(instance_name);
    let socket_path = lima_instance_dir.join("ha.sock");
    Ok(socket_path.exists())
}

/// Create a Lima instance from a YAML file
fn create_lima_instance(instance_name: &str, config_path: &Path) -> Result<()> {
    let status = Command::new("limactl")
        .args([
            "create",
            "--tty=false",
            "--name",
            instance_name,
            config_path
                .to_str()
                .context("Lima config path contains invalid UTF-8")?,
        ])
        .status()
        .context("failed to execute limactl create")?;

    if !status.success() {
        anyhow::bail!("failed to create Lima instance");
    }

    Ok(())
}

/// Delete a Lima instance
fn delete_lima_instance(instance_name: &str) -> Result<()> {
    let status = Command::new("limactl")
        .args(["delete", "--force", instance_name])
        .status()
        .context("failed to execute limactl delete")?;

    if !status.success() {
        anyhow::bail!("failed to delete Lima instance");
    }

    Ok(())
}

/// Start a Lima instance by name
fn start_lima_instance(instance_name: &str) -> Result<()> {
    let status = Command::new("limactl")
        .args(["start", "--tty=false", instance_name])
        .status()
        .context("failed to execute limactl start")?;

    if !status.success() {
        anyhow::bail!("failed to start Lima instance");
    }

    Ok(())
}

/// Ensure Lima instance exists and is running
pub fn ensure_instance(instance: &InstanceModel, worktree_dir: &Path) -> Result<()> {
    let lima_home = get_lima_home()?;
    let lima_instance_dir = lima_home.join(&instance.name);

    // Write YAML configuration to the worktree directory (not to home)
    let local_yaml_path = worktree_dir.join("lima.yaml");
    write_lima_yaml(instance, &local_yaml_path)?;
    println!(
        "lima-devshell: wrote lima.yaml to {}",
        local_yaml_path.display()
    );

    // Check if instance already exists
    if !lima_instance_dir.exists() {
        println!(
            "lima-devshell: creating Lima instance '{}'...",
            instance.name
        );
        create_lima_instance(&instance.name, &local_yaml_path)?;
        start_lima_instance(&instance.name)?;
    } else {
        // Check if instance is running
        let is_running = is_instance_running(&instance.name)?;

        if !is_running {
            // Try to start the existing instance
            println!(
                "lima-devshell: starting existing Lima instance '{}'...",
                instance.name
            );

            // If start fails, the instance might have invalid config - delete and recreate
            if start_lima_instance(&instance.name).is_err() {
                println!(
                    "lima-devshell: instance failed to start, deleting and recreating '{}'...",
                    instance.name
                );
                delete_lima_instance(&instance.name)?;
                create_lima_instance(&instance.name, &local_yaml_path)?;
                start_lima_instance(&instance.name)?;
            }
        }
    }

    Ok(())
}

/// Enter Lima VM and start Nix devshell
pub fn enter_devshell(instance: &InstanceModel, ctx: &AppContext) -> Result<()> {
    let script = build_guest_script(ctx);

    let status = Command::new("limactl")
        .args(["shell", &instance.name, "--", "bash", "-lc", &script])
        .status()
        .context("failed to execute limactl shell")?;

    if !status.success() {
        anyhow::bail!("failed to enter Lima devshell");
    }

    Ok(())
}
