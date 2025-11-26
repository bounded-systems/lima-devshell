use crate::app::{AppContext, InstanceModel};
use crate::script::build_guest_script;
use anyhow::{Context as AnyhowContext, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::io::Write;
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

#[derive(Debug, Serialize, Deserialize)]
struct Image {
    location: String,
    arch: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct Mount {
    location: String,
    #[serde(rename = "mountPoint")]
    mount_point: String,
    writable: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct SshConfig {
    #[serde(rename = "localPort")]
    local_port: u16,
    #[serde(rename = "loadDotSSHPubKeys")]
    load_dot_ssh_pub_keys: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct ProvisionStep {
    mode: String,
    script: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct LimaConfig {
    #[serde(rename = "vmType")]
    vm_type: String,
    arch: String,
    images: Vec<Image>,
    mounts: Vec<Mount>,
    memory: String,
    cpus: u32,
    disk: String,
    ssh: SshConfig,
    env: HashMap<String, String>,
    provision: Vec<ProvisionStep>,
}

/// Generate Lima YAML configuration from instance model
#[cfg(test)]
pub fn generate_lima_yaml(instance: &InstanceModel) -> Result<String> {
    generate_lima_yaml_impl(instance)
}

/// Internal implementation of YAML generation
fn generate_lima_yaml_impl(instance: &InstanceModel) -> Result<String> {
    let config = LimaConfig {
        vm_type: VM_TYPE.to_string(),
        arch: ARCH.to_string(),
        images: vec![Image {
            location: UBUNTU_IMAGE_URL.to_string(),
            arch: ARCH.to_string(),
        }],
        mounts: vec![
            Mount {
                location: instance.worktree_mount_host.display().to_string(),
                mount_point: instance.worktree_mount_guest.clone(),
                writable: true,
            },
            Mount {
                location: instance.bare_repo_mount_host.display().to_string(),
                mount_point: instance.bare_repo_mount_guest.clone(),
                writable: true,
            },
        ],
        memory: MEMORY.to_string(),
        cpus: CPUS,
        disk: DISK.to_string(),
        ssh: SshConfig {
            local_port: 0,
            load_dot_ssh_pub_keys: true,
        },
        env: {
            let mut env = HashMap::new();
            env.insert("LIMA_WORKDIR_DISABLED".to_string(), "1".to_string());
            env
        },
        provision: vec![ProvisionStep {
            mode: "system".to_string(),
            script: r#"#!/bin/sh
# Create user if not present
if ! id dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash dev
  passwd -d dev
  usermod -aG sudo dev
fi
"#
            .to_string(),
        }],
    };

    // Add comment header
    let yaml =
        serde_yaml::to_string(&config).context("failed to serialize Lima configuration to YAML")?;
    Ok(format!(
        "# Lima instance for {} development\n{}",
        instance.repo_name, yaml
    ))
}

/// Write Lima YAML configuration to a specific path
fn write_lima_yaml(instance: &InstanceModel, yaml_path: &Path) -> Result<()> {
    let yaml_content = generate_lima_yaml_impl(instance)?;
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

/// Start a Lima instance from a YAML file
/// This will create the instance if it doesn't exist, or start it if it exists but is stopped.
/// Uses --tty=false (via --yes) to ensure non-interactive operation.
fn start_lima_instance_with_yaml(instance_name: &str, config_path: &Path) -> Result<()> {
    let config_path_str = config_path
        .to_str()
        .context("Lima config path contains invalid UTF-8")?;

    // Use limactl start with YAML file - this will create if needed and start the instance
    // --yes (alias for --tty=false) ensures non-interactive operation with no prompts
    // This is the recommended automation pattern per Lima docs
    let status = Command::new("limactl")
        .args([
            "start",
            "--yes", // Non-interactive mode, no prompts
            "--name",
            instance_name,
            config_path_str, // Path to YAML file
        ])
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .context("failed to execute limactl start")?;

    if !status.success() {
        anyhow::bail!("failed to start Lima instance");
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

/// Start a Lima instance by name (for instances that already exist)
/// Uses --tty=false (via --yes) to ensure non-interactive operation.
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

    // Start the instance with YAML file - this will create if needed and start it
    // Using limactl start with YAML is the recommended automation pattern
    // It handles both "create if needed" and "start if stopped" in one command
    println!(
        "lima-devshell: ensuring Lima instance '{}' is created and running...",
        instance.name
    );
    start_lima_instance_with_yaml(&instance.name, &local_yaml_path)?;

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::InstanceModel;
    use std::path::PathBuf;

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

    #[test]
    fn test_generate_lima_yaml_structure() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        // Verify YAML contains expected fields
        assert!(yaml.contains("vmType: vz"));
        assert!(yaml.contains("arch: aarch64"));
        assert!(yaml.contains("memory: 6GiB"));
        assert!(yaml.contains("cpus: 4"));
        assert!(yaml.contains("disk: 80GiB"));
        assert!(yaml.contains("localPort: 0"));
        assert!(yaml.contains("LIMA_WORKDIR_DISABLED"));
        assert!(yaml.contains("test-repo")); // repo name in comment
    }

    #[test]
    fn test_generate_lima_yaml_mounts() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        // Verify mounts are present
        assert!(yaml.contains("/Users/test/worktree"));
        assert!(yaml.contains("/worktrees/test/repo"));
        assert!(yaml.contains("/Users/test/bare.git"));
        assert!(yaml.contains("writable: true"));
    }

    #[test]
    fn test_generate_lima_yaml_provision() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        // Verify provision script is present
        assert!(yaml.contains("mode: system"));
        assert!(yaml.contains("useradd"));
        assert!(yaml.contains("dev"));
    }

    #[test]
    fn test_generate_lima_yaml_valid_yaml() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        // Verify it's valid YAML by parsing it
        let parsed: Result<LimaConfig, _> = serde_yaml::from_str(&yaml);
        assert!(
            parsed.is_ok(),
            "Generated YAML should be valid: {:?}",
            parsed.err()
        );

        let config = parsed.unwrap();
        assert_eq!(config.vm_type, "vz");
        assert_eq!(config.arch, "aarch64");
        assert_eq!(config.memory, "6GiB");
        assert_eq!(config.cpus, 4);
        assert_eq!(config.ssh.local_port, 0);
        assert!(config.ssh.load_dot_ssh_pub_keys);
        assert_eq!(config.mounts.len(), 2);
        assert_eq!(config.provision.len(), 1);
    }

    #[test]
    fn test_generate_lima_yaml_ssh_config() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        // Verify SSH config uses non-interactive defaults
        // localPort: 0 means auto-assign (good for automation)
        let parsed: LimaConfig = serde_yaml::from_str(&yaml).expect("valid YAML");
        assert_eq!(parsed.ssh.local_port, 0, "localPort should be 0 for auto-assign");
        assert!(
            parsed.ssh.load_dot_ssh_pub_keys,
            "loadDotSSHPubKeys should be true"
        );
    }

    #[test]
    fn test_generate_lima_yaml_env_vars() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        let parsed: LimaConfig = serde_yaml::from_str(&yaml).expect("valid YAML");
        assert_eq!(
            parsed.env.get("LIMA_WORKDIR_DISABLED"),
            Some(&"1".to_string())
        );
    }
}
