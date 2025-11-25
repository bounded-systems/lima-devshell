use crate::git_ctx::{determine_lima_instance, is_git_worktree, resolve_bare_repo_path};
use crate::paths::{get_host_worktree_root, get_relative_path, guest_path_for};
use anyhow::{Context, Result};
use clap::Parser;
use std::env;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "lima-devshell")]
#[command(about = "Enter Lima dev environment from a valid Git worktree")]
pub struct Args {
    /// Target directory (defaults to current directory)
    #[arg(short, long)]
    pub directory: Option<PathBuf>,
}

/// Context containing all derived information about the target directory
pub struct AppContext {
    pub target_dir_host: PathBuf,
    pub host_worktree_root: PathBuf,
    pub rel_path: String,
    pub guest_worktree_root: String,
    pub guest_cwd: String,
    pub path_segments: Vec<String>,
    pub lima_instance: String,
    pub bare_repo_path: PathBuf,
    pub bare_repo_mount_name: String,
}

/// Instance model describing what mounts and configuration a Lima instance needs
pub struct InstanceModel {
    pub name: String,
    pub worktree_mount_host: PathBuf,
    pub worktree_mount_guest: String,
    pub bare_repo_mount_host: PathBuf,
    pub bare_repo_mount_guest: String,
    pub bare_repo_mount_name: String,
    pub repo_name: String,
}

impl AppContext {
    /// Build context from CLI arguments
    pub fn from_args(args: Args) -> Result<Self> {
        let target_dir = match args.directory {
            Some(dir) => dir,
            None => env::current_dir().context("failed to get current directory")?,
        };

        // Guard 1: Require that we are inside a Git work tree
        if !is_git_worktree(&target_dir)? {
            anyhow::bail!("error: current directory is not inside a Git work tree");
        }

        // Guard 2: Require that the current directory is under the host worktree root
        let host_worktree_root = get_host_worktree_root()?;
        let rel_path = get_relative_path(&target_dir, &host_worktree_root)
            .context("current directory is not under the host worktree root")?;

        // Compute the equivalent path inside Lima
        let guest_worktree_root = "/worktrees".to_string();
        let guest_cwd = guest_path_for(&rel_path);

        // Extract repo name and worktree name from path to determine Lima instance name
        let path_segments: Vec<String> = rel_path.split('/').map(|s| s.to_string()).collect();
        let path_segments_refs: Vec<&str> = path_segments.iter().map(|s| s.as_str()).collect();
        let lima_instance = determine_lima_instance(&path_segments_refs)?;

        // Try to get bare repo path from git
        let bare_repo_path = resolve_bare_repo_path(&target_dir)?;

        let bare_repo_mount_name = bare_repo_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("repo.git")
            .to_string();

        Ok(AppContext {
            target_dir_host: target_dir,
            host_worktree_root,
            rel_path,
            guest_worktree_root,
            guest_cwd,
            path_segments,
            lima_instance,
            bare_repo_path,
            bare_repo_mount_name,
        })
    }
}

impl InstanceModel {
    /// Build instance model from context
    pub fn from_context(ctx: &AppContext) -> Result<Self> {
        let repo_name = if ctx.path_segments.len() >= 3 {
            ctx.path_segments[2].clone()
        } else {
            "repo".to_string()
        };

        Ok(InstanceModel {
            name: ctx.lima_instance.clone(),
            worktree_mount_host: ctx.target_dir_host.clone(),
            worktree_mount_guest: ctx.guest_cwd.clone(),
            bare_repo_mount_host: ctx.bare_repo_path.clone(),
            bare_repo_mount_guest: format!("/git/bare/{}", ctx.bare_repo_mount_name),
            bare_repo_mount_name: ctx.bare_repo_mount_name.clone(),
            repo_name,
        })
    }
}

/// Main orchestration function
pub fn run() -> Result<()> {
    let args = Args::parse();
    let ctx = AppContext::from_args(args)?;
    let instance = InstanceModel::from_context(&ctx)?;

    println!("lima-devshell: host:  {}", ctx.target_dir_host.display());
    println!("lima-devshell: guest: {}", ctx.guest_cwd);
    println!("lima-devshell: instance: {}", ctx.lima_instance);
    println!("lima-devshell: bare repo: {}", ctx.bare_repo_path.display());

    crate::lima::ensure_instance(&instance)?;
    crate::lima::enter_devshell(&instance, &ctx)?;

    Ok(())
}
