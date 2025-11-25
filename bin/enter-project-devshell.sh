#!/usr/bin/env bash
# Helper script to enter a project devshell from the bootstrap shell
# This script validates the environment and launches the project's nix develop

set -euo pipefail

# Expected mount paths inside Lima VM
WORKTREES_ROOT="/worktrees"
BOOTSTRAP_FLAKE_PATH="/worktrees/io.github/bdelanghe/lima-devshell"

# Get target directory (passed as first argument or use current directory)
TARGET_DIR="${1:-$(pwd)}"

# Normalize path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "[lima-devshell] target directory: $TARGET_DIR"

# Guard: Verify we're under the worktrees root
case "$TARGET_DIR" in
  "$WORKTREES_ROOT"/*)
    echo "[lima-devshell] path is under $WORKTREES_ROOT ✓"
    ;;
  *)
    echo "[lima-devshell] error: target directory is not under $WORKTREES_ROOT" >&2
    echo "[lima-devshell]   target: $TARGET_DIR" >&2
    echo "[lima-devshell]   expected root: $WORKTREES_ROOT" >&2
    exit 1
    ;;
esac

# Guard: Verify we're in a Git worktree
if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[lima-devshell] error: target directory is not inside a Git work tree" >&2
  echo "[lima-devshell]   target: $TARGET_DIR" >&2
  exit 1
fi

# Guard: Verify the directory exists and has a flake.nix
if [ ! -f "$TARGET_DIR/flake.nix" ]; then
  echo "[lima-devshell] warning: no flake.nix found in $TARGET_DIR" >&2
  echo "[lima-devshell] continuing anyway (may fail if nix develop requires flake)" >&2
fi

# Change to target directory
cd "$TARGET_DIR"
echo "[lima-devshell] now in: $(pwd)"

# Launch the project's devshell
echo "[lima-devshell] launching project devshell..."
exec nix develop

