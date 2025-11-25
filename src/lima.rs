use crate::app::{AppContext, InstanceModel};
use crate::script::build_guest_script;
use anyhow::{Context as AnyhowContext, Result};
use std::collections::hash_map::DefaultHasher;
use std::env;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

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
/// Returns true if the instance was started by create, false otherwise
fn create_lima_instance(instance_name: &str, config_path: &Path) -> Result<bool> {
    let config_path_str = config_path
        .to_str()
        .context("Lima config path contains invalid UTF-8")?;
    
    // Use --yes to skip the "Do you want to start the instance now?" prompt
    // Answer "n" via echo to skip starting during create (we'll start separately)
    let status = Command::new("sh")
        .arg("-c")
        .arg(format!(
            "echo 'n' | limactl create --yes --name {} {}",
            instance_name, config_path_str
        ))
        .status()
        .context("failed to execute limactl create")?;

    if !status.success() {
        anyhow::bail!("failed to create Lima instance");
    }

    // We answered "n", so instance was not started
    Ok(false)
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
        .args(["start", "--yes", instance_name])
        .status()
        .context("failed to execute limactl start")?;

    if !status.success() {
        anyhow::bail!("failed to start Lima instance");
    }

    Ok(())
}

/// Wait for Lima instance to be fully ready (guest agent connected)
fn wait_for_instance_ready(instance_name: &str, max_wait_seconds: u64) -> Result<()> {
    println!(
        "lima-devshell: waiting for instance '{}' to be ready...",
        instance_name
    );

    for i in 0..max_wait_seconds {
        // Try to run a simple command to check if the instance is ready
        let status = Command::new("limactl")
            .args(["shell", instance_name, "--", "echo", "ready"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();

        if let Ok(exit_status) = status {
            if exit_status.success() {
                println!("lima-devshell: instance '{}' is ready", instance_name);
                return Ok(());
            }
        }

        if i < max_wait_seconds - 1 {
            thread::sleep(Duration::from_secs(1));
        }
    }

    anyhow::bail!(
        "instance '{}' did not become ready within {} seconds",
        instance_name,
        max_wait_seconds
    );
}

/// Clean up old "dev" instance that might have invalid YAML
fn cleanup_old_dev_instance() -> Result<()> {
    let lima_home = get_lima_home()?;
    let dev_instance_dir = lima_home.join("dev");

    if dev_instance_dir.exists() {
        println!("lima-devshell: cleaning up old 'dev' instance with invalid configuration...");
        // Ignore errors - the instance might not exist or already be deleted
        let _ = delete_lima_instance("dev");
    }

    Ok(())
}

/// Ensure Lima instance exists and is running
pub fn ensure_instance(instance: &InstanceModel, worktree_dir: &Path) -> Result<()> {
    let lima_home = get_lima_home()?;
    let lima_instance_dir = lima_home.join(&instance.name);

    // Clean up old "dev" instance that might have invalid YAML
    cleanup_old_dev_instance()?;

    // Write YAML configuration to the worktree directory (not to home)
    let local_yaml_path = worktree_dir.join("lima.yaml");
    write_lima_yaml(instance, &local_yaml_path)?;
    println!(
        "lima-devshell: wrote lima.yaml to {}",
        local_yaml_path.display()
    );

    // Check if instance already exists
    if lima_instance_dir.exists() {
        // Check if instance is running
        let is_running = is_instance_running(&instance.name)?;

        if is_running {
            // Instance is running, we're good
            return Ok(());
        }

        // Instance exists but isn't running - delete it to ensure clean state
        // This prevents issues with stale/cached YAML configurations
        println!(
            "lima-devshell: deleting existing instance '{}' to ensure clean configuration...",
            instance.name
        );
        delete_lima_instance(&instance.name)?;
    }

    // Create and start the instance with fresh configuration
    println!(
        "lima-devshell: creating Lima instance '{}'...",
        instance.name
    );
    let was_started = create_lima_instance(&instance.name, &local_yaml_path)?;

    // Only start if create didn't start it (we answered "n" to the prompt)
    if !was_started {
        start_lima_instance(&instance.name)?;
    }

    // Wait for the instance to be fully ready (guest agent connected)
    wait_for_instance_ready(&instance.name, 60)?;

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
