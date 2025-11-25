{
  description = "Launchable programs module - deterministic tool wrappers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Project root path (git repo root) - non-flake path input
    # Default to parent directory for standalone use, overridden by parent via follows
    project-root.url = "path:..";
    project-root.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, project-root, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # All tools come from nixpkgs input (deterministic)
        cargo = pkgs.cargo;
        findutils = pkgs.findutils;
        # Project root from input
        projectRoot = toString project-root;
      in
      {
        apps = {
          # Pre-Nix preparation: impure operation to prepare inputs for deterministic builds
          # Nix's buildRustPackage uses Cargo.lock + cargoHash to download and verify dependencies
          # No vendoring needed - Nix handles dependency fetching and caching
          impure-flake-prep = {
            type = "app";
            meta = {
              description = "Prepare Rust project for Nix: generate Cargo.lock";
            };
            program = toString (pkgs.writeShellScript "impure-flake-prep" ''
              set -euo pipefail
              # Use current directory (where user runs the command), not store path
              # User should run this from the project root
              
              # Ensure cargo is available (from nixpkgs input)
              export PATH="${cargo}/bin:$PATH"
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  Rust → Nix Preparation"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              
              # Lock dependencies - REQUIRED for Nix
              # Nix's buildRustPackage uses Cargo.lock + cargoHash to:
              # - Download dependencies from crates.io
              # - Verify hashes
              # - Cache in /nix/store
              echo "Locking dependencies..."
              ${cargo}/bin/cargo generate-lockfile
              echo "  ✓ Cargo.lock generated"
              echo ""
              
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "  ✓ Preparation complete"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "Next steps:"
              echo "  1. Commit Cargo.lock for reproducible Nix builds"
              echo "  2. Build with: nix build"
              echo ""
              echo "Note: Nix will download and cache dependencies automatically."
              echo "      No vendoring needed - buildRustPackage handles it."
            '');
          };

          # Update all flake.lock files in root and .flakes/ subdirectories
          # Impure operation: modifies flake.lock files in the project directory
          impure-update-flakes = {
            type = "app";
            meta = {
              description = "Update flake.lock files for all flakes in root and .flakes/ directories (impure)";
            };
            program = toString (pkgs.writeShellScript "impure-update-flakes" ''
              set -euo pipefail
              
              # Use current directory (where user runs the command), not store path
              # User should run this from the project root
              PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
              cd "$PROJECT_ROOT" || { echo "Error: Cannot access project root: $PROJECT_ROOT" >&2; exit 1; }
              PROJECT_ROOT=$(pwd)
              
              # Use system nix (Determinate Systems) from PATH
              # Ensure find and git are available
              export PATH="${findutils}/bin:$PATH"
              
              # Track stashes created during updates (use regular array, not local)
              created_stashes=()
              
              # Function to stash lock file changes after each update
              stash_lock_changes() {
                local flake_dir="$1"
                if git rev-parse --git-dir >/dev/null 2>&1; then
                  # Stash the specific lock file for this flake directory
                  local lock_file="$flake_dir/flake.lock"
                  if [ -f "$lock_file" ]; then
                    # Check if the lock file has changes
                    if ! git diff-index --quiet HEAD -- "$lock_file" 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard "$lock_file" 2>/dev/null)" ]; then
                      # Add the lock file to staging if it's not already tracked
                      git add -f "$lock_file" 2>/dev/null || true
                      # Stash only this specific lock file
                      stash_msg="temp: impure-update-flakes-lock-$(date +%s)-$(basename "$flake_dir")"
                      if git stash push -m "$stash_msg" -- "$lock_file" >/dev/null 2>&1; then
                        created_stashes+=("$stash_msg")
                      fi
                    fi
                  fi
                fi
              }
              
              # Restore function to be called on exit
              restore_changes() {
                if [ "''${#created_stashes[@]}" -gt 0 ]; then
                  echo ""
                  echo "Restoring stashed lock file changes..."
                  # Pop stashes in reverse order (newest first)
                  local stash_count="''${#created_stashes[@]}"
                  for ((i=stash_count-1; i>=0; i--)); do
                    if git stash pop >/dev/null 2>&1; then
                      echo "  ✓ Restored lock file from stash $((i+1))/$stash_count"
                    else
                      echo "  ⚠ Warning: Could not restore stash $((i+1))/$stash_count"
                    fi
                  done
                  echo ""
                fi
              }
              trap restore_changes EXIT
              
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
                    # Don't stash if nothing changed - keep the lock file in the work tree
                  else
                    echo "  ⚠ No changes: Lock file unchanged (inputs already up to date)"
                    update_success=true  # Still count as success, just no changes needed
                    ((already_up_to_date++))
                    # Don't stash if nothing changed
                    return
                  fi
                else
                  # If that failed, try without --no-warn-dirty
                  update_output=$(cd "$flake_dir" && nix flake update 2>&1)
                  if [ $? -eq 0 ]; then
                    update_success=true
                  else
                    # Show error message
                    if echo "$update_output" | grep -q "uncommitted changes"; then
                      echo "  ⚠ Skipped: Uncommitted changes detected"
                    else
                      echo "  Error: $(echo "$update_output" | head -1)"
                    fi
                  fi
                fi
                
                if [ "$update_success" = true ]; then
                  # Verify the lock file was actually written
                  if [ -f "$lock_file" ]; then
                    echo "  ✓ Updated successfully"
                    ((updated++))
                    # Stash lock file changes after successful update to keep repo clean for next update
                    stash_lock_changes "$flake_dir"
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
            '');
          };
        };
      }
    );
}
