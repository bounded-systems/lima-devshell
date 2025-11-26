#!/usr/bin/env bash
# Update all flake.lock files in root and .flakes/ subdirectories
# Impure operation: modifies flake.lock files in the project directory

set -euo pipefail

# Use current directory (where user runs the command), not store path
# User should run this from the project root
PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
cd "$PROJECT_ROOT" || { echo "Error: Cannot access project root: $PROJECT_ROOT" >&2; exit 1; }
PROJECT_ROOT=$(pwd)

# Use system nix (Determinate Systems) from PATH
# Ensure find and git are available
export PATH="${FINDUTILS_BIN}:$PATH"

# Track commits made during updates
commits_made=0

# Function to commit lock file after each update
commit_lock_file() {
  local flake_dir="$1"
  local flake_name="$2"
  local lock_file="$flake_dir/flake.lock"
  
  if [ ! -f "$lock_file" ]; then
    return
  fi
  
  # Check if we're in a git repo
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    return
  fi
  
  # Check if lock file has changes
  if git diff --quiet "$lock_file" 2>/dev/null && git diff --cached --quiet "$lock_file" 2>/dev/null; then
    # No changes to commit
    return
  fi
  
  # Add and commit the lock file
  if git add "$lock_file" >/dev/null 2>&1; then
    if git commit -m "chore: update flake.lock for $flake_name" >/dev/null 2>&1; then
      ((commits_made++))
      echo "  ✓ Committed lock file"
    fi
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Flake Update Tool"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# Collect all flakes first (using temp file to avoid subshell issues)
temp_file=$(mktemp)
trap "rm -f $temp_file" EXIT

# Add root flake if it exists
if [ -f "$PROJECT_ROOT/flake.nix" ]; then
  echo "root|$PROJECT_ROOT" >> "$temp_file"
fi

# Find all flakes in .flakes/ directory and subdirectories
# Use a separate temp file for find output to avoid subshell issues
find_temp=$(mktemp)
if [ -d "$PROJECT_ROOT/.flakes" ]; then
  # First, add .flakes/flake.nix if it exists (depth 1)
  if [ -f "$PROJECT_ROOT/.flakes/flake.nix" ]; then
    echo ".flakes|$PROJECT_ROOT/.flakes" >> "$temp_file"
  fi
  # Then find flakes in subdirectories (depth 2)
  find "$PROJECT_ROOT/.flakes" -mindepth 2 -maxdepth 2 -name "flake.nix" -type f 2>/dev/null > "$find_temp" || true
  while read -r flake_file; do
    flake_dir=$(dirname "$flake_file")
    flake_name=".flakes/$(basename "$flake_dir")"
    echo "$flake_name|$flake_dir" >> "$temp_file"
  done < "$find_temp"
  rm -f "$find_temp"
fi

# Count flakes
flake_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")

# List all flakes found
if [ "$flake_count" -eq 0 ]; then
  echo "No flakes found to update."
  exit 0
fi

echo "Found $flake_count flake(s):"
line_num=1
while IFS='|' read -r flake_name flake_dir; do
  echo "  $line_num. $flake_name"
  echo "     $flake_dir"
  ((line_num++))
done < "$temp_file"
echo ""

# Track success/failure
updated=0
already_up_to_date=0
failed=0
failed_dirs=()

# Function to update a flake in a directory
update_flake() {
  local flake_dir="$1"
  local flake_name="$2"
  
  echo "Updating: $flake_name"
  echo "  Directory: $flake_dir"
  
  # Check if directory is writable (not a Nix store path)
  if [[ "$flake_dir" == /nix/store/* ]]; then
    echo "  ⚠ Skipping: Directory is in Nix store (read-only)"
    echo "  Hint: Run this command from your project directory, not via nix run"
    ((failed++))
    failed_dirs+=("$flake_name (read-only)")
    echo ""
    return
  fi
  
  # Ensure directory is writable
  if [ ! -w "$flake_dir" ]; then
    echo "  ✗ Directory is not writable"
    ((failed++))
    failed_dirs+=("$flake_name")
    echo ""
    return
  fi
  
  # Update the flake
  # Check lock file before update to detect if it actually changes
  local lock_file="$flake_dir/flake.lock"
  local lock_before=""
  if [ -f "$lock_file" ]; then
    lock_before=$(md5sum "$lock_file" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$lock_file" 2>/dev/null | cut -d' ' -f1 || echo "")
  fi
  
  # Try to update the flake (capture output to check for actual updates)
  local update_output
  update_output=$(cd "$flake_dir" && nix flake update --no-warn-dirty 2>&1)
  local update_exit=$?
  
  if [ $update_exit -eq 0 ]; then
    # Check if lock file actually changed
    local lock_after=""
    local actually_changed=false
    if [ -f "$lock_file" ]; then
      lock_after=$(md5sum "$lock_file" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$lock_file" 2>/dev/null | cut -d' ' -f1 || echo "")
      if [ -n "$lock_before" ] && [ -n "$lock_after" ] && [ "$lock_before" != "$lock_after" ]; then
        actually_changed=true
      elif [ -z "$lock_before" ] && [ -n "$lock_after" ]; then
        actually_changed=true
      fi
    fi
    
    # Check if nix reported any updates in the output
    if echo "$update_output" | grep -qE "(Updated|Added) input"; then
      actually_changed=true
    fi
    
    if [ "$actually_changed" = true ]; then
      update_success=true
    else
      echo "  ⚠ No changes: Lock file unchanged (inputs already up to date)"
      update_success=true  # Still count as success, just no changes needed
      ((already_up_to_date++))
      return
    fi
  else
    # Check for specific error types in the output
    if echo "$update_output" | grep -qE "(HTTP error 403|unable to download|rate limit)"; then
      echo "  ⚠ Network error: GitHub API rate limit or authentication issue"
      echo "  Hint: Wait a few minutes and try again, or check your GitHub token"
    elif echo "$update_output" | grep -q "uncommitted changes"; then
      echo "  ⚠ Skipped: Uncommitted changes detected"
    else
      # Show first meaningful error line
      local error_line=$(echo "$update_output" | grep -i "error" | head -1 || echo "$update_output" | head -1)
      if [ -n "$error_line" ]; then
        echo "  Error: $error_line"
      fi
    fi
    # Don't try again without --no-warn-dirty if we got a network error
    # The issue is likely not related to uncommitted changes
  fi
  
  if [ "$update_success" = true ]; then
    # Verify the lock file was actually written
    if [ -f "$lock_file" ]; then
      echo "  ✓ Updated successfully"
      ((updated++))
      # Commit lock file immediately after successful update to keep repo clean
      commit_lock_file "$flake_dir" "$flake_name"
    else
      echo "  ✗ Update failed: Lock file not found after update"
      ((failed++))
      failed_dirs+=("$flake_name")
    fi
  else
    echo "  ✗ Update failed"
    echo "  Note: This may be due to uncommitted changes or network issues"
    ((failed++))
    failed_dirs+=("$flake_name")
  fi
  echo ""
}

# Update all collected flakes
# Disable exit on error for the loop to ensure all flakes are processed
set +e
while IFS='|' read -r flake_name flake_dir || [ -n "$flake_name" ]; do
  [ -z "$flake_name" ] && continue
  update_flake "$flake_dir" "$flake_name" || true
done < "$temp_file"
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Updated:        $updated"
echo "  Already up to date: $already_up_to_date"
echo "  Failed:          $failed"
if [ $commits_made -gt 0 ]; then
  echo "  Commits made:   $commits_made"
fi

if [ $failed -gt 0 ]; then
  echo ""
  echo "Failed flakes:"
  for dir in "''${failed_dirs[@]}"; do
    echo "  - $dir"
  done
  exit 1
fi

echo ""
echo "✓ All flakes updated successfully"

