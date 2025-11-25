use crate::app::{Context, InstanceModel};
use crate::script::build_guest_script;
use anyhow::{Context as AnyhowContext, Result};
use std::collections::hash_map::DefaultHasher;
use std::env;
use std::hash::{Hash, Hasher};
use std::path::PathBuf;
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
  user: "dev"
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

/// Write Lima YAML configuration to instance directory
fn write_lima_yaml(instance: &InstanceModel) -> Result<()> {
    let home = env::var("HOME").context("HOME environment variable not set")?;
    let lima_instance_dir = PathBuf::from(format!("{}/.lima/{}", home, instance.name));

    std::fs::create_dir_all(&lima_instance_dir)
        .context("failed to create Lima instance directory")?;

    let yaml_content = generate_lima_yaml(instance);
    let yaml_path = lima_instance_dir.join("lima.yaml");

    std::fs::write(&yaml_path, yaml_content).context("failed to write Lima YAML configuration")?;

    Ok(())
}

/// Check if a Lima instance is currently running
fn is_instance_running(instance_name: &str) -> Result<bool> {
    let home = env::var("HOME").context("HOME environment variable not set")?;
    let lima_instance_dir = PathBuf::from(format!("{}/.lima/{}", home, instance_name));
    let socket_path = lima_instance_dir.join("ha.sock");
    Ok(socket_path.exists())
}

/// Start a Lima instance
fn start_lima_instance(instance_name: &str, config_path: Option<&PathBuf>) -> Result<()> {
    let args = if let Some(path) = config_path {
        vec![
            "start",
            path.to_str()
                .context("Lima config path contains invalid UTF-8")?,
        ]
    } else {
        vec!["start", instance_name]
    };

    let status = Command::new("limactl")
        .args(&args)
        .status()
        .context("failed to execute limactl")?;

    if !status.success() {
        anyhow::bail!("failed to start Lima instance");
    }

    Ok(())
}

/// Ensure Lima instance exists and is running
pub fn ensure_instance(instance: &InstanceModel) -> Result<()> {
    let home = env::var("HOME").context("HOME environment variable not set")?;
    let lima_instance_dir = PathBuf::from(format!("{}/.lima/{}", home, instance.name));

    if !lima_instance_dir.exists() {
        println!(
            "lima-devshell: creating Lima instance '{}'...",
            instance.name
        );
        write_lima_yaml(instance)?;

        let yaml_path = lima_instance_dir.join("lima.yaml");
        start_lima_instance(&instance.name, Some(&yaml_path))?;
    } else {
        // Check if instance is running
        let is_running = is_instance_running(&instance.name)?;

        if !is_running {
            println!(
                "lima-devshell: starting existing Lima instance '{}'...",
                instance.name
            );
            start_lima_instance(&instance.name, None)?;
        }
    }

    Ok(())
}

/// Enter Lima VM and start Nix devshell
pub fn enter_devshell(instance: &InstanceModel, ctx: &Context) -> Result<()> {
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
