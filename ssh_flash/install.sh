#!/bin/bash
# SSH Push Tool Installation Script
# Linux-only installation

set -e

echo "SSH Push Tool Installation"
echo "=========================="

# Run cleanup first to ensure clean installation
echo "Running cleanup to remove any existing installations..."
if [[ -f "$(dirname "$0")/cleanup.sh" ]]; then
    bash "$(dirname "$0")/cleanup.sh"
    echo ""
fi

# Check if we're on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "Error: This tool is designed for Linux systems only."
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    echo "Please install Python 3 and try again."
    exit 1
fi

# Check if SSH client is available
if ! command -v ssh &> /dev/null; then
    echo "Error: SSH client is required but not installed."
    echo "Please install OpenSSH client and try again."
    exit 1
fi

# Check if SCP is available
if ! command -v scp &> /dev/null; then
    echo "Error: SCP is required but not installed."
    echo "Please install OpenSSH client (includes SCP) and try again."
    exit 1
fi

echo "✓ Python 3 found: $(python3 --version)"
echo "✓ SSH client found: $(ssh -V 2>&1)"
echo "✓ SCP found: $(scp -V 2>&1 | head -n1)"

# Ensure dos2unix is installed
if ! command -v dos2unix &> /dev/null; then
    echo "Installing dos2unix (required for line ending conversion)..."
    sudo apt-get update && sudo apt-get install -y dos2unix
fi

echo "Converting files to Unix (LF) line endings..."
dos2unix ssh-push
dos2unix ssh_push.py

# Check and fix shebang only if needed
expected_shebang='#!/bin/bash'
actual_shebang=$(head -n 1 ssh-push | tr -d '\r\n')
if [ "$actual_shebang" != "$expected_shebang" ]; then
    echo "Fixing broken shebang in ssh-push..."
    tail -n +2 ssh-push > ssh-push.tmp
    echo "$expected_shebang" > ssh-push
    cat ssh-push.tmp >> ssh-push
    rm ssh-push.tmp
else
    echo "✓ Shebang is correct"
fi

chmod +x ssh-push

echo "Installing ssh-push to /usr/local/bin/..."
sudo cp ssh-push /usr/local/bin/
echo "✓ ssh-push installed to /usr/local/bin/"

# Verify installation
echo ""
echo "Verifying installation..."
if [[ -f "/usr/local/bin/ssh-push" ]]; then
    echo "✓ ssh-push file exists in /usr/local/bin/"
else
    echo "✗ ssh-push file NOT found in /usr/local/bin/"
    exit 1
fi

if [[ -x "/usr/local/bin/ssh-push" ]]; then
    echo "✓ ssh-push is executable"
else
    echo "✗ ssh-push is NOT executable"
    exit 1
fi

# Check if /usr/local/bin is in PATH
if echo "$PATH" | grep -q "/usr/local/bin"; then
    echo "✓ /usr/local/bin is in PATH"
else
    echo "⚠ /usr/local/bin is NOT in PATH"
    echo "Current PATH: $PATH"
fi

# Test if command is accessible
if command -v ssh-push &> /dev/null; then
    echo "✓ ssh-push command is accessible"
else
    echo "⚠ ssh-push command is NOT accessible in current session"
    echo "This might be due to shell caching. Try:"
    echo "  hash -r"
    echo "  or restart your terminal"
fi

echo ""
echo "Installation complete!"
echo "✓ ssh-push installed to /usr/local/bin/"
echo ""
echo "If ssh-push doesn't work in other terminals, try:"
echo "  hash -r"
echo "  or restart those terminals" 