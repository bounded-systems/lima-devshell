#!/usr/bin/env bash
set -euo pipefail

# Accept optional directory argument or use PROJECT_ROOT env var or current directory
project_root="${1:-${PROJECT_ROOT:-$PWD}}"
project_root="$(cd "$project_root" && pwd)"
cd "$project_root"

echo "Formatting files in: $project_root"

echo "Formatting Nix files..."
# Format all nix files including .flakes directory
# nixpkgs-fmt can handle multiple files at once
find . -name "*.nix" -type f -print0 | xargs -0 -r nixpkgs-fmt

echo "Formatting Rust files..."
if [ -f "Cargo.toml" ]; then
	# Count Rust files
	rust_file_count=$(find . -name "*.rs" -type f | wc -l | tr -d ' ')
	if [ "$rust_file_count" -gt 0 ]; then
		echo "Found $rust_file_count Rust file(s)"
		cargo fmt --all || {
			echo "Warning: cargo fmt failed or made no changes" >&2
			exit 0
		}
		echo "Rust formatting complete"
	else
		echo "No Rust files found, skipping Rust formatting"
	fi
else
	echo "No Cargo.toml found, skipping Rust formatting"
fi

echo "Formatting shell files..."
# Format shell files (sh, bash, zsh)
shell_file_count=$(find . -name "*.sh" -o -name "*.bash" -o -name "*.zsh" | wc -l | tr -d ' ')
if [ "$shell_file_count" -gt 0 ]; then
	echo "Found $shell_file_count shell file(s)"
	find . \( -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \) -type f -print0 | xargs -0 -r shfmt -w -s || {
		echo "Warning: shfmt failed or made no changes" >&2
		exit 0
	}
	echo "Shell formatting complete"
else
	echo "No shell files found, skipping shell formatting"
fi
