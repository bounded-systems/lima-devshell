use anyhow::{Context, Result};
use clap::Parser;
use git2::Repository;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Parser, Debug)]
#[command(name = "lima-devshell")]
#[command(about = "Enter Lima dev environment from a valid Git worktree")]
struct Args {
    /// Target directory (defaults to current directory)
    #[arg(short, long)]
    directory: Option<PathBuf>,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let target_dir = args
        .directory
        .unwrap_or_else(|| env::current_dir().unwrap());

    // Guard 1: Require that we are inside a Git work tree
    if !is_git_worktree(&target_dir)? {
        anyhow::bail!("error: current directory is not inside a Git work tree");
    }

    // Guard 2: Require that the current directory is under the host worktree root
    let host_worktree_root = get_host_worktree_root()?;
    let rel_path = get_relative_path(&target_dir, &host_worktree_root)
        .context("current directory is not under the host worktree root")?;

    // Compute the equivalent path inside Lima
    let guest_worktree_root = "/worktrees";
    let cwd_guest = format!("{}/{}", guest_worktree_root, rel_path);

    // Extract repo name and worktree name from path to determine Lima instance name
    let path_segments: Vec<&str> = rel_path.split('/').collect();
    let lima_instance = determine_lima_instance(&path_segments)?;

    // Try to get bare repo path from git
    let bare_repo_path = get_bare_repo_path(&target_dir, &path_segments)?;

    let bare_repo_mount_name = bare_repo_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("repo.git");

    println!("lima-devshell: host:  {}", target_dir.display());
    println!("lima-devshell: guest: {}", cwd_guest);
    println!("lima-devshell: instance: {}", lima_instance);
    println!("lima-devshell: bare repo: {}", bare_repo_path.display());

    // Ensure Lima instance exists and is configured
    ensure_lima_instance(
        &lima_instance,
        &target_dir,
        &cwd_guest,
        &bare_repo_path,
        bare_repo_mount_name,
        &path_segments,
    )?;

    // Enter Lima and start Nix devshell
    enter_lima_devshell(&lima_instance, &cwd_guest)?;

    Ok(())
}

fn is_git_worktree(dir: &Path) -> Result<bool> {
    // Use git2 crate to check if we're in a git repository
    match Repository::discover(dir) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

fn get_host_worktree_root() -> Result<PathBuf> {
    let xdg_state_home = env::var("XDG_STATE_HOME")
        .unwrap_or_else(|_| format!("{}/.local/state", env::var("HOME").unwrap()));
    Ok(PathBuf::from(format!("{}/git/worktrees", xdg_state_home)))
}

fn get_relative_path(target: &Path, root: &Path) -> Result<String> {
    let target = target.canonicalize()?;
    let root = root.canonicalize()?;

    target
        .strip_prefix(&root)
        .map(|p| p.to_string_lossy().to_string())
        .context("target is not under root")
}

fn determine_lima_instance(path_segments: &[&str]) -> Result<String> {
    match path_segments.len() {
        n if n >= 4 => {
            let repo_owner = path_segments[1];
            let repo_name = path_segments[2];
            let worktree_name = path_segments[3].to_lowercase();
            Ok(format!("{}-{}-{}", repo_owner, repo_name, worktree_name))
        }
        3 => {
            let repo_owner = path_segments[1];
            let repo_name = path_segments[2];
            Ok(format!("{}-{}", repo_owner, repo_name))
        }
        2 => Ok(path_segments[1].to_string()),
        _ => anyhow::bail!("unexpected worktree path structure"),
    }
}

fn get_bare_repo_path(target_dir: &Path, path_segments: &[&str]) -> Result<PathBuf> {
    // Try to get bare repo path using git2
    match Repository::discover(target_dir) {
        Ok(repo) => {
            let workdir = repo.workdir();
            if let Some(workdir) = workdir {
                // This is a worktree, try to find the bare repo
                let git_dir = repo.path();
                
                // Check if .git is a file (worktree case)
                if git_dir.is_file() {
                    let content = fs::read_to_string(git_dir)?;
                    if let Some(gitdir) = content.strip_prefix("gitdir: ") {
                        let gitdir_path = PathBuf::from(gitdir.trim());
                        // Navigate up from worktrees/<name>/ to get bare repo
                        if let Some(parent) = gitdir_path.parent().and_then(|p| p.parent()) {
                            return Ok(parent.to_path_buf());
                        }
                    }
                } else if git_dir.is_dir() {
                    // Regular repo, bare repo is the parent
                    if let Some(parent) = git_dir.parent() {
                        return Ok(parent.to_path_buf());
                    }
                }
            }
        }
        Err(_) => {
            // Not a git repo, fall through to fallback
        }
    }

    // Fallback: construct expected bare repo path
    if path_segments.len() >= 3 {
        let repo_owner = path_segments[1];
        let repo_name = path_segments[2];
        let home = env::var("HOME")?;
        Ok(PathBuf::from(format!(
            "{}/.local/share/git/bare/io.github/{}/{}.git",
            home, repo_owner, repo_name
        )))
    } else {
        anyhow::bail!("cannot determine bare repo path")
    }
}

fn ensure_lima_instance(
    lima_instance: &str,
    cwd_host: &Path,
    cwd_guest: &str,
    bare_repo_path: &Path,
    bare_repo_mount_name: &str,
    path_segments: &[&str],
) -> Result<()> {
    let home = env::var("HOME")?;
    let lima_instance_dir = PathBuf::from(format!("{}/.lima/{}", home, lima_instance));

    if !lima_instance_dir.exists() {
        println!("lima-devshell: creating Lima instance '{}'...", lima_instance);
        std::fs::create_dir_all(&lima_instance_dir)?;

        // Generate Lima config
        let repo_name = if path_segments.len() >= 3 {
            path_segments[2]
        } else {
            "repo"
        };

        let lima_config = format!(
            r#"# Lima instance for {} development
vmType: "vz"
arch: "aarch64"

images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"

mounts:
  # Mount this specific worktree
  - location: "{}"
    mountPoint: "{}"
    writable: true
  # Mount the bare repo
  - location: "{}"
    mountPoint: "/git/bare/{}"
    writable: true

memory: "6GiB"
cpus: 4
disk: "80GiB"

ssh:
  user: "dev"
  localPort: 60022
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
            repo_name,
            cwd_host.display(),
            cwd_guest,
            bare_repo_path.display(),
            bare_repo_mount_name
        );

        std::fs::write(lima_instance_dir.join("lima.yaml"), lima_config)?;

        // Start Lima instance
        let status = Command::new("limactl")
            .args(["start", lima_instance_dir.join("lima.yaml").to_str().unwrap()])
            .status()?;

        if !status.success() {
            anyhow::bail!("failed to start Lima instance");
        }
    } else {
        // Check if instance is running by examining the instance directory
        // Lima creates a socket file when running
        let socket_path = lima_instance_dir.join("ha.sock");
        let is_running = socket_path.exists();

        if !is_running {
            println!(
                "lima-devshell: starting existing Lima instance '{}'...",
                lima_instance
            );
            let status = Command::new("limactl")
                .args(["start", lima_instance])
                .status()?;

            if !status.success() {
                anyhow::bail!("failed to start Lima instance");
            }
        }
    }

    Ok(())
}

fn enter_lima_devshell(lima_instance: &str, cwd_guest: &str) -> Result<()> {
    let worktrees_root = "/worktrees";
    let bootstrap_flake_path = "/worktrees/io.github/bdelanghe/lima-devshell";

    // Build the script that runs inside Lima VM with all validations
    // Note: We use {{ to escape { in the format string, and }} to escape }
    // For bash ${1:-default}, we need ${{{{1:-default}}}} to get ${1:-default} in output
    let script = format!(
        r#"
set -euo pipefail

# Get target directory (use provided path or current directory)
TARGET_DIR="${{{{1:-{}}}}}" 
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "[lima-devshell] target directory: $TARGET_DIR"

# Guard: Verify we're under the worktrees root
case "$TARGET_DIR" in
  {}/*)
    echo "[lima-devshell] path is under {} ✓"
    ;;
  *)
    echo "[lima-devshell] error: target directory is not under {}" >&2
    echo "[lima-devshell]   target: $TARGET_DIR" >&2
    echo "[lima-devshell]   expected root: {}" >&2
    exit 1
    ;;
esac

# Guard: Verify we're in a Git worktree
if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[lima-devshell] error: target directory is not inside a Git work tree" >&2
  echo "[lima-devshell]   target: $TARGET_DIR" >&2
  exit 1
fi

# Guard: Verify the directory exists and has a flake.nix (warning only)
if [ ! -f "$TARGET_DIR/flake.nix" ]; then
  echo "[lima-devshell] warning: no flake.nix found in $TARGET_DIR" >&2
  echo "[lima-devshell] continuing anyway (may fail if nix develop requires flake)" >&2
fi

# Change to target directory
cd "$TARGET_DIR"
echo "[lima-devshell] now in: $(pwd)"

# Launch the project's devshell
echo "[lima-devshell] launching project devshell..."

# First try to enter bootstrap shell, then project shell
if [ -d '{}' ]; then
  nix develop '{}' --command bash -lc 'nix develop'
else
  echo "[lima-devshell] warning: bootstrap flake not found at {}" >&2
  echo "[lima-devshell] trying GitHub URL..." >&2
  nix develop github:bdelanghe/lima-devshell --command bash -lc 'nix develop' || {{
    echo "[lima-devshell] falling back to direct nix develop" >&2
    exec nix develop
  }}
fi
"#,
        cwd_guest,
        worktrees_root,
        worktrees_root,
        worktrees_root,
        worktrees_root,
        worktrees_root,
        bootstrap_flake_path,
        bootstrap_flake_path,
        bootstrap_flake_path
    );

    Command::new("limactl")
        .args(["shell", lima_instance, "--", "bash", "-lc", &script])
        .status()?;

    Ok(())
}
