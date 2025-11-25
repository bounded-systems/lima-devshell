use anyhow::{Context, Result};
use git2::Repository;
use std::fs;
use std::path::{Path, PathBuf};

/// Check if a directory is inside a Git worktree
pub fn is_git_worktree(dir: &Path) -> Result<bool> {
    match Repository::discover(dir) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

/// Resolve the bare repository path from a worktree directory
/// Uses git2 to discover the repository and navigate to the bare repo
pub fn resolve_bare_repo_path(target_dir: &Path) -> Result<PathBuf> {
    let repo = Repository::discover(target_dir).context("failed to discover Git repository")?;

    let workdir = repo
        .workdir()
        .context("repository has no work directory (bare repo?)")?;

    let git_dir = repo.path();

    // Check if .git is a file (worktree case)
    if git_dir.is_file() {
        let content = fs::read_to_string(git_dir).context("failed to read .git file")?;

        if let Some(gitdir) = content.strip_prefix("gitdir: ") {
            let gitdir_path = PathBuf::from(gitdir.trim());
            // Navigate up from worktrees/<name>/ to get bare repo
            if let Some(parent) = gitdir_path.parent().and_then(|p| p.parent()) {
                return Ok(parent.to_path_buf());
            }
        }
        anyhow::bail!("could not determine bare repo path from worktree .git file");
    } else if git_dir.is_dir() {
        // Regular repo, bare repo is the parent
        if let Some(parent) = git_dir.parent() {
            return Ok(parent.to_path_buf());
        }
        anyhow::bail!("could not determine bare repo path: git_dir has no parent");
    }

    anyhow::bail!("could not determine bare repo path: unexpected git_dir structure");
}

/// Determine Lima instance name from path segments
pub fn determine_lima_instance(path_segments: &[&str]) -> Result<String> {
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
