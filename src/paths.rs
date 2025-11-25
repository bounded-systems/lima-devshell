use anyhow::{Context as AnyhowContext, Result};
use std::env;
use std::path::{Path, PathBuf};

pub const GUEST_WORKTREE_ROOT: &str = "/worktrees";

/// Get XDG_STATE_HOME directory, falling back to ~/.local/state
pub fn xdg_state_home() -> Result<PathBuf> {
    let xdg_state_home = match env::var("XDG_STATE_HOME") {
        Ok(val) => val,
        Err(_) => {
            let home = env::var("HOME").context("HOME environment variable not set")?;
            format!("{}/.local/state", home)
        }
    };
    Ok(PathBuf::from(xdg_state_home))
}

/// Get the host worktree root directory
pub fn get_host_worktree_root() -> Result<PathBuf> {
    let xdg_state_home = xdg_state_home()?;
    Ok(xdg_state_home.join("git/worktrees"))
}

/// Get the relative path of target under root
pub fn get_relative_path(target: &Path, root: &Path) -> Result<String> {
    let target = target.canonicalize()?;
    let root = root.canonicalize()?;

    target
        .strip_prefix(&root)
        .map(|p| p.to_string_lossy().to_string())
        .context("target is not under root")
}

/// Compute the guest path for a given relative path
pub fn guest_path_for(rel_path: &str) -> String {
    format!("{}/{}", GUEST_WORKTREE_ROOT, rel_path)
}
