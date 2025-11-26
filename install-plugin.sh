#!/bin/sh
# Install limactl-devshell plugin wrapper
# This script creates a symlink to make lima-devshell available as a Lima plugin

set -eu

# Default installation location
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SCRIPT="$SCRIPT_DIR/limactl-devshell"

# Check if plugin script exists
if [ ! -f "$PLUGIN_SCRIPT" ]; then
    echo "Error: limactl-devshell not found at $PLUGIN_SCRIPT" >&2
    exit 1
fi

# Check if plugin script is executable
if [ ! -x "$PLUGIN_SCRIPT" ]; then
    echo "Making limactl-devshell executable..."
    chmod +x "$PLUGIN_SCRIPT"
fi

# Create symlink
TARGET="$INSTALL_DIR/limactl-devshell"

if [ -L "$TARGET" ]; then
    echo "Plugin already installed at $TARGET"
    echo "Removing existing symlink..."
    rm "$TARGET"
elif [ -f "$TARGET" ]; then
    echo "Warning: $TARGET already exists and is not a symlink" >&2
    echo "Please remove it manually and run this script again" >&2
    exit 1
fi

echo "Installing limactl-devshell plugin..."
echo "  From: $PLUGIN_SCRIPT"
echo "  To:   $TARGET"

# Create parent directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# Create symlink
ln -s "$PLUGIN_SCRIPT" "$TARGET"

echo ""
echo "✓ Plugin installed successfully!"
echo ""
echo "Verify installation:"
echo "  limactl --help | grep devshell"
echo ""
echo "Use the plugin:"
echo "  limactl devshell --help"

