#!/bin/bash
# Update Flash Tool

set -e

echo "Flash Tool Update"
echo "================"

# Check if flash command exists
if ! command -v flash &> /dev/null; then
    echo "Error: flash command is not installed."
    echo "Run ./install.sh first to install the tool."
    exit 1
fi

# Get the current directory (should be the repository root)
REPO_DIR="$(pwd)"
FLASH_SCRIPT="$REPO_DIR/flash_fpga.py"

# Check if this is a git repository
if [[ -d ".git" ]]; then
    echo "Pulling latest changes from git..."
    git pull
    echo "✓ Git pull completed"
else
    echo "Warning: Not a git repository. Skipping git pull."
fi

# Check if we're in the right directory
if [[ ! -f "$FLASH_SCRIPT" ]]; then
    echo "Error: flash_fpga.py not found in $REPO_DIR"
    echo "Make sure you're running this from the repository root directory."
    exit 1
fi

echo "Updating flash tool from repository..."

# Convert line endings if needed
if command -v dos2unix &> /dev/null; then
    echo "Converting flash_fpga.py to Unix line endings..."
    dos2unix "$FLASH_SCRIPT"
else
    echo "Warning: dos2unix not found. Line endings may not be converted."
fi

# Make executable
chmod +x "$FLASH_SCRIPT"

# Update the flash alias in shell configuration
echo "Updating flash command alias..."

# Detect shell
SHELL_CONFIG=""
if [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
    echo "Detected zsh shell"
elif [[ "$SHELL" == *"bash"* ]]; then
    SHELL_CONFIG="$HOME/.bashrc"
    echo "Detected bash shell"
else
    echo "Warning: Unknown shell ($SHELL). Trying .bashrc..."
    SHELL_CONFIG="$HOME/.bashrc"
fi

# Remove old flash alias if it exists
if grep -q "alias flash=" "$SHELL_CONFIG" 2>/dev/null; then
    echo "Removing old flash alias..."
    grep -v "alias flash=" "$SHELL_CONFIG" > "$SHELL_CONFIG.tmp"
    mv "$SHELL_CONFIG.tmp" "$SHELL_CONFIG"
fi

# Add new flash alias
echo "" >> "$SHELL_CONFIG"
echo "# Flash Tool" >> "$SHELL_CONFIG"
echo "alias flash=\"python3 $FLASH_SCRIPT\"" >> "$SHELL_CONFIG"

echo "✓ Flash tool updated successfully!"
echo "To activate the changes, run:"
echo "  source $SHELL_CONFIG"
echo "  or restart your terminal"
echo ""
echo "You can then use: flash --help" 