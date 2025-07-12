#!/bin/bash
# Update SSH Push Tool

set -e

echo "SSH Push Tool Update"
echo "==================="

# Check if ssh-push is installed
if [[ ! -f "/usr/local/bin/ssh-push" ]]; then
    echo "Error: ssh-push is not installed."
    echo "Run ./install.sh first to install the tool."
    exit 1
fi

# Get the current directory (should be the repository root)
REPO_DIR="$(pwd)"
SSH_FLASH_DIR="$REPO_DIR/ssh_flash"

# Check if this is a git repository
if [[ -d ".git" ]]; then
    echo "Pulling latest changes from git..."
    git pull
    echo "✓ Git pull completed"
else
    echo "Warning: Not a git repository. Skipping git pull."
fi

# Check if we're in the right directory
if [[ ! -f "$SSH_FLASH_DIR/ssh-push" ]]; then
    echo "Error: ssh-push file not found in $SSH_FLASH_DIR"
    echo "Make sure you're running this from the repository root directory."
    exit 1
fi

echo "Updating ssh-push from repository..."

# Convert line endings and fix shebang if needed
if command -v dos2unix &> /dev/null; then
    echo "Converting ssh-push to Unix line endings..."
    dos2unix "$SSH_FLASH_DIR/ssh-push"
else
    echo "Warning: dos2unix not found. Line endings may not be converted."
fi

# Check and fix shebang if needed
expected_shebang='#!/bin/bash'
actual_shebang=$(head -n 1 "$SSH_FLASH_DIR/ssh-push" | tr -d '\r\n')
if [ "$actual_shebang" != "$expected_shebang" ]; then
    echo "Fixing shebang in ssh-push..."
    tail -n +2 "$SSH_FLASH_DIR/ssh-push" > "$SSH_FLASH_DIR/ssh-push.tmp"
    echo "$expected_shebang" > "$SSH_FLASH_DIR/ssh-push"
    cat "$SSH_FLASH_DIR/ssh-push.tmp" >> "$SSH_FLASH_DIR/ssh-push"
    rm "$SSH_FLASH_DIR/ssh-push.tmp"
fi

# Make executable
chmod +x "$SSH_FLASH_DIR/ssh-push"

# Copy to /usr/local/bin/
echo "Installing updated version to /usr/local/bin/..."
sudo cp "$SSH_FLASH_DIR/ssh-push" /usr/local/bin/

echo "✓ ssh-push updated successfully!"
echo "You can now use the updated version: ssh-push --help" 