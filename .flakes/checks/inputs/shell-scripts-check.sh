#!/usr/bin/env bash
set -euo pipefail

# Check shell scripts in the checks flake inputs directory only
# This script should be run from the checks flake directory

echo "Checking shell scripts in checks/inputs/ directory..."

INPUTS_DIR="./inputs"
VIOLATIONS=0
TOTAL_SCRIPTS=0

if [ ! -d "$INPUTS_DIR" ]; then
  echo "Error: $INPUTS_DIR not found"
  exit 1
fi

# Find all .sh files in inputs directory
while IFS= read -r -d '' script_file; do
  TOTAL_SCRIPTS=$((TOTAL_SCRIPTS + 1))
  script_name=$(basename "$script_file")
  echo "  Checking $script_name..."
  
  # Check 1: Syntax validation using bash -n
  if ! bash -n "$script_file" 2>&1; then
    echo "    ✗ Syntax error in $script_file"
    VIOLATIONS=$((VIOLATIONS + 1))
    continue
  fi
  
  # Check 2: Should have shebang
  if ! head -1 "$script_file" | grep -qE '^#!/'; then
    echo "    ✗ Missing shebang in $script_file"
    VIOLATIONS=$((VIOLATIONS + 1))
    continue
  fi
  
  # Check 3: Should use bash (recommended for consistency)
  if head -1 "$script_file" | grep -qE '^#!/.*sh[^a]'; then
    echo "    ⚠ Warning: $script_file uses generic sh, consider using bash for consistency"
    # Not a violation, just a warning
  fi
  
  # Check 4: Should have set -euo pipefail or similar safety settings
  if ! grep -qE 'set\s+-[euo]' "$script_file"; then
    echo "    ⚠ Warning: $script_file may be missing 'set -euo pipefail' or similar safety settings"
    # Not a violation, just a warning
  fi
  
  echo "    ✓ $script_name passed checks"
done < <(find "$INPUTS_DIR" -name "*.sh" -type f -print0 2>/dev/null || true)

echo ""
if [ $VIOLATIONS -gt 0 ]; then
  echo "Found $VIOLATIONS violation(s) in $TOTAL_SCRIPTS script(s)."
  exit 1
fi

if [ $TOTAL_SCRIPTS -eq 0 ]; then
  echo "No shell scripts found in inputs directory."
else
  echo "✓ All $TOTAL_SCRIPTS shell script(s) passed validation."
fi
