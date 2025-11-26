use crate::app::AppContext;
use crate::paths::GUEST_WORKTREE_ROOT;
use std::env;

// Note: This module depends on app::AppContext, so it must be declared after app module

/// Get the bootstrap flake path, either from environment variable or use a placeholder
/// Users should set LIMA_DEVSHELL_BOOTSTRAP_PATH if they need a specific bootstrap flake
fn get_bootstrap_flake_path() -> String {
    env::var("LIMA_DEVSHELL_BOOTSTRAP_PATH")
        .unwrap_or_else(|_| "/worktrees/lima-devshell".to_string())
}

/// Get the bootstrap flake GitHub URL, either from environment variable or use a placeholder
/// Users should set LIMA_DEVSHELL_BOOTSTRAP_GITHUB if they need a specific GitHub URL
fn get_bootstrap_github_url() -> String {
    env::var("LIMA_DEVSHELL_BOOTSTRAP_GITHUB")
        .unwrap_or_else(|_| "github:owner/lima-devshell".to_string())
}

/// Build the bash script that runs inside the Lima VM
/// This script validates the environment and launches the project's nix develop
pub fn build_guest_script(ctx: &AppContext) -> String {
    let bootstrap_path = get_bootstrap_flake_path();
    let bootstrap_github = get_bootstrap_github_url();
    
    // Note: We use {{ to escape { in the format string, and }} to escape }
    // For bash ${1:-default}, we need ${{1:-{}}} to get ${1:-default} in output
    format!(
        r#"
set -euo pipefail

# Get target directory (use provided path or current directory)
TARGET_DIR="${{1:-{}}}" 
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
  nix develop {} --command bash -lc 'nix develop' || {{
    echo "[lima-devshell] falling back to direct nix develop" >&2
    exec nix develop
  }}
fi
"#,
        ctx.guest_cwd,
        GUEST_WORKTREE_ROOT,
        GUEST_WORKTREE_ROOT,
        GUEST_WORKTREE_ROOT,
        GUEST_WORKTREE_ROOT,
        bootstrap_path,
        bootstrap_path,
        bootstrap_github
    )
}
