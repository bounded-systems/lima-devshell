use crate::app::{AppContext, InstanceModel};
use crate::script::build_guest_script;
use anyhow::{Context as AnyhowContext, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

// Lima VM configuration constants
pub const MEMORY: &str = "6GiB";
pub const CPUS: u32 = 4;
pub const DISK: &str = "80GiB";

/// Detect the appropriate VM type based on the host machine
/// - macOS (any): `vz` (best performance, native hypervisor)
/// - Linux: `qemu` (standard for Linux hosts)
/// - Windows: `wsl2` (if Lima supports it)
fn detect_vm_type() -> &'static str {
    match std::env::consts::OS {
        "macos" => "vz",
        "linux" => "qemu",
        "windows" => "wsl2",
        _ => "qemu", // Default fallback
    }
}

/// Detect the appropriate architecture based on the host machine
/// Maps host architecture to Lima VM architecture
fn detect_arch() -> &'static str {
    match std::env::consts::ARCH {
        "aarch64" | "arm64" => "aarch64",
        "x86_64" => "x86_64",
        _ => "x86_64", // Default fallback
    }
}

/// Get the Ubuntu cloud image URL based on the detected architecture
fn get_ubuntu_image_url(arch: &str) -> String {
    match arch {
        "aarch64" => {
            "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img".to_string()
        }
        "x86_64" => {
            "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img".to_string()
        }
        _ => {
            "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img".to_string()
        }
    }
}

/// Determine if Rosetta should be enabled
/// Rosetta is available for VZ instances on ARM hosts (macOS >= 13.0)
/// It provides fast Intel-on-ARM emulation
fn should_enable_rosetta(vm_type: &str) -> bool {
    vm_type == "vz" && std::env::consts::OS == "macos" && detect_arch() == "aarch64"
}

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
struct GuestAgent {
    enabled: bool,
    #[serde(rename = "logPath", skip_serializing_if = "Option::is_none")]
    log_path: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Rosetta {
    enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    binfmt: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PortForward {
    #[serde(rename = "guestIP", skip_serializing_if = "Option::is_none")]
    guest_ip: Option<String>,
    #[serde(rename = "guestPort", skip_serializing_if = "Option::is_none")]
    guest_port: Option<u16>,
    #[serde(rename = "guestPortRange", skip_serializing_if = "Option::is_none")]
    guest_port_range: Option<String>,
    #[serde(rename = "hostIP", skip_serializing_if = "Option::is_none")]
    host_ip: Option<String>,
    #[serde(rename = "hostPort", skip_serializing_if = "Option::is_none")]
    host_port: Option<u16>,
    #[serde(rename = "hostPortRange", skip_serializing_if = "Option::is_none")]
    host_port_range: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    proto: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    ignore: Option<bool>,
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
    #[serde(rename = "guestAgent", skip_serializing_if = "Option::is_none")]
    guest_agent: Option<GuestAgent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    rosetta: Option<Rosetta>,
    // Explicitly set port forwarding rules (empty for Nix devshells - all access via limactl shell)
    // This makes it clear we're intentionally not forwarding any ports
    #[serde(rename = "portForwards", skip_serializing_if = "Vec::is_empty")]
    port_forwards: Vec<PortForward>,
}

/// Generate Lima YAML configuration from instance model
#[cfg(test)]
pub fn generate_lima_yaml(instance: &InstanceModel) -> Result<String> {
    generate_lima_yaml_impl(instance)
}

/// Internal implementation of YAML generation
fn generate_lima_yaml_impl(instance: &InstanceModel) -> Result<String> {
    let vm_type = detect_vm_type();
    let arch = detect_arch();
    let image_url = get_ubuntu_image_url(arch);
    let enable_rosetta = should_enable_rosetta(vm_type);

    let config = LimaConfig {
        vm_type: vm_type.to_string(),
        arch: arch.to_string(),
        images: vec![Image {
            location: image_url,
            arch: arch.to_string(),
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
        // SSH configuration: localPort 0 means auto-assign
        // No explicit network config = default user-mode network (host-only/localhost)
        // This is perfect for Nix devshells: connect via limactl shell or 127.0.0.1
        // Port forwarding is explicitly set to empty (see port_forwards below)
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
        guest_agent: Some(GuestAgent {
            enabled: true,
            log_path: Some("/var/log/lima-guest-agent.log".to_string()),
        }),
        rosetta: if enable_rosetta {
            Some(Rosetta {
                enabled: true,
                binfmt: Some(true), // Register rosetta to /proc/sys/fs/binfmt_misc for container support
            })
        } else {
            None
        },
        // Explicitly set empty port forwards for Nix devshells
        // All access is via limactl shell (SSH) on localhost - no port forwarding needed
        // This makes the configuration explicit rather than relying on defaults
        port_forwards: Vec::new(),
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
/// Uses `limactl list --json` to get actual state, not just socket existence
fn is_instance_running(instance_name: &str) -> Result<bool> {
    let output = Command::new("limactl")
        .args(["list", "--json", instance_name])
        .output()
        .context("failed to execute limactl list")?;

    if !output.status.success() {
        // If instance doesn't exist, limactl returns non-zero
        // This is fine - instance is not running
        return Ok(false);
    }

    let stdout =
        String::from_utf8(output.stdout).context("limactl list output is not valid UTF-8")?;

    // Parse JSON output - limactl list --json returns an array of instances
    let instances: Vec<Value> =
        serde_json::from_str(&stdout).context("failed to parse limactl list JSON output")?;

    // Find the instance with matching name
    for instance in instances {
        if let Some(name) = instance.get("name").and_then(|n| n.as_str()) {
            if name == instance_name {
                // Check the status field - "Running" means it's actually running
                if let Some(status) = instance.get("status").and_then(|s| s.as_str()) {
                    return Ok(status == "Running");
                }
            }
        }
    }

    // Instance not found in list, so it's not running
    Ok(false)
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

/// Stop a Lima instance gracefully
/// Uses --tty=false (via --yes) to ensure non-interactive operation.
fn stop_lima_instance(instance_name: &str) -> Result<()> {
    // Don't fail if stop fails - instance might already be stopped
    // This is a best-effort cleanup operation
    let _ = Command::new("limactl")
        .args(["stop", "--yes", instance_name])
        .status()
        .context("failed to execute limactl stop");

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
    // Write instance name to .lima-devshell file for direnv to read
    let lima_devshell_path = worktree_dir.join(".lima-devshell");
    std::fs::write(&lima_devshell_path, &instance.name)
        .context("failed to write .lima-devshell file")?;
    println!(
        "lima-devshell: wrote instance name to {}",
        lima_devshell_path.display()
    );

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

        // Instance exists but isn't running - stop it first (best effort)
        // This ensures any hostagent processes are properly cleaned up
        println!(
            "lima-devshell: stopping existing instance '{}' before cleanup...",
            instance.name
        );
        let _ = stop_lima_instance(&instance.name);
        // Wait a moment for cleanup to complete
        thread::sleep(Duration::from_secs(2));

        // Then delete it to ensure clean state
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

    // Retry logic for port conflicts - sometimes stale processes hold ports
    let max_retries = 3;
    for attempt in 1..=max_retries {
        match start_lima_instance_with_yaml(&instance.name, &local_yaml_path) {
            Ok(_) => break,
            Err(e) => {
                let error_msg = e.to_string();
                // Check if this is a port conflict error
                if attempt < max_retries
                    && (error_msg.contains("address already in use") || error_msg.contains("bind"))
                {
                    println!(
                        "lima-devshell: port conflict detected, retrying (attempt {}/{})...",
                        attempt, max_retries
                    );
                    // Force cleanup and retry
                    let _ = stop_lima_instance(&instance.name);
                    let _ = delete_lima_instance(&instance.name);
                    thread::sleep(Duration::from_secs(2));
                    continue;
                } else {
                    return Err(e);
                }
            }
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::InstanceModel;
    use std::path::PathBuf;

    #[test]
    fn test_detect_vm_type() {
        let vm_type = detect_vm_type();
        
        // Verify we get a valid VM type (not empty)
        assert!(!vm_type.is_empty(), "VM type should not be empty");
        
        // Verify we're not hitting the fallback on common platforms
        match std::env::consts::OS {
            "macos" => assert_eq!(vm_type, "vz", "macOS should use vz VM type"),
            "linux" => assert_eq!(vm_type, "qemu", "Linux should use qemu VM type"),
            "windows" => assert_eq!(vm_type, "wsl2", "Windows should use wsl2 VM type"),
            _ => {
                // Unknown platform - should fallback to qemu
                assert_eq!(vm_type, "qemu", "Unknown platform should fallback to qemu");
                // Log a warning that we're on an untested platform
                eprintln!("WARNING: Running on untested platform: {}", std::env::consts::OS);
            }
        }
        
        // Verify it's one of the valid VM types
        assert!(
            matches!(vm_type, "vz" | "qemu" | "wsl2"),
            "VM type should be one of: vz, qemu, wsl2, got: {}",
            vm_type
        );
    }

    #[test]
    fn test_detect_arch() {
        let arch = detect_arch();
        
        // Verify we get a valid architecture (not empty)
        assert!(!arch.is_empty(), "Architecture should not be empty");
        
        // Verify we're not hitting the fallback on common architectures
        match std::env::consts::ARCH {
            "aarch64" | "arm64" => {
                assert_eq!(arch, "aarch64", "ARM64 should map to aarch64");
            }
            "x86_64" => {
                assert_eq!(arch, "x86_64", "x86_64 should map to x86_64");
            }
            _ => {
                // Unknown architecture - should fallback to x86_64
                assert_eq!(arch, "x86_64", "Unknown architecture should fallback to x86_64");
                // Log a warning that we're on an untested architecture
                eprintln!("WARNING: Running on untested architecture: {}", std::env::consts::ARCH);
            }
        }
        
        // Verify it's one of the valid architectures
        assert!(
            matches!(arch, "aarch64" | "x86_64"),
            "Architecture should be one of: aarch64, x86_64, got: {}",
            arch
        );
    }

    #[test]
    fn test_detect_vm_type_and_arch_consistency() {
        // Verify that VM type and arch are consistent with host platform
        let vm_type = detect_vm_type();
        let arch = detect_arch();
        let os = std::env::consts::OS;
        
        // macOS should use vz
        if os == "macos" {
            assert_eq!(vm_type, "vz", "macOS must use vz VM type");
        }
        
        // Verify arch matches host architecture
        match std::env::consts::ARCH {
            "aarch64" | "arm64" => assert_eq!(arch, "aarch64"),
            "x86_64" => assert_eq!(arch, "x86_64"),
            _ => {} // Unknown arch, fallback is acceptable
        }
    }

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

        // Verify YAML contains expected fields (using detected host values)
        let vm_type = detect_vm_type();
        let arch = detect_arch();
        assert!(yaml.contains(&format!("vmType: {}", vm_type)));
        assert!(yaml.contains(&format!("arch: {}", arch)));
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
        // Verify VM type and arch match detected host values
        assert_eq!(config.vm_type, detect_vm_type());
        assert_eq!(config.arch, detect_arch());
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
        assert_eq!(
            parsed.ssh.local_port, 0,
            "localPort should be 0 for auto-assign"
        );
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

    #[test]
    fn test_generate_lima_yaml_guest_agent() {
        let instance = create_test_instance();
        let yaml = generate_lima_yaml(&instance).expect("should generate YAML");

        // Verify guest agent configuration is present
        assert!(yaml.contains("guestAgent:"));
        assert!(yaml.contains("enabled: true"));
        assert!(yaml.contains("logPath:"));
        assert!(yaml.contains("/var/log/lima-guest-agent.log"));

        let parsed: LimaConfig = serde_yaml::from_str(&yaml).expect("valid YAML");
        assert!(parsed.guest_agent.is_some());
        let guest_agent = parsed.guest_agent.unwrap();
        assert!(guest_agent.enabled);
        assert_eq!(
            guest_agent.log_path,
            Some("/var/log/lima-guest-agent.log".to_string())
        );
    }
}
