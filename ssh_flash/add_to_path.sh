#!/bin/bash
# Add ssh_flash directory to PATH

set -e

echo "Adding ssh_flash to PATH..."
echo "=========================="

# Get the current directory (ssh_flash)
SSH_FLASH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check if PATH already contains the directory
if grep -q "$SSH_FLASH_DIR" "$SHELL_CONFIG" 2>/dev/null; then
    echo "✓ ssh_flash directory is already in PATH"
    echo "Current PATH entry: $SSH_FLASH_DIR"
else
    # Add to PATH
    echo "" >> "$SHELL_CONFIG"
    echo "# SSH Push Tool" >> "$SHELL_CONFIG"
    echo "export PATH=\"\$PATH:$SSH_FLASH_DIR\"" >> "$SHELL_CONFIG"
    
    echo "✓ Added ssh_flash to PATH in $SHELL_CONFIG"
    echo "Added: export PATH=\"\$PATH:$SSH_FLASH_DIR\""
fi

echo ""
echo "To activate the changes, run one of these commands:"
echo "  source $SHELL_CONFIG"
echo "  or restart your terminal"
echo ""
echo "After that, you can run 'ssh_push --help' from anywhere!" 