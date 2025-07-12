#!/bin/bash
# SSH Push Tool Cleanup Script
# Removes any existing installations when repository is cloned

set -e

echo "SSH Push Tool Cleanup"
echo "===================="

# Remove ssh-push from /usr/local/bin/ if it exists
if [[ -f "/usr/local/bin/ssh-push" ]]; then
    echo "Removing existing ssh-push from /usr/local/bin/..."
    sudo rm -f /usr/local/bin/ssh-push
    echo "✓ Removed existing ssh-push installation"
else
    echo "✓ No existing ssh-push installation found"
fi

# Clean up PATH entries from shell configuration files
SHELL_CONFIGS=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile")

for config_file in "${SHELL_CONFIGS[@]}"; do
    if [[ -f "$config_file" ]]; then
        # Check if this config file contains ssh_flash PATH entries
        if grep -q "ssh_flash" "$config_file" 2>/dev/null; then
            echo "Cleaning up PATH entries in $config_file..."
            
            # Create a backup
            cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Remove lines containing ssh_flash
            grep -v "ssh_flash" "$config_file" > "$config_file.tmp"
            mv "$config_file.tmp" "$config_file"
            
            echo "✓ Cleaned up PATH entries in $config_file"
        else
            echo "✓ No PATH entries found in $config_file"
        fi
    fi
done

# Remove configuration file if it exists (local to current directory)
CONFIG_FILE=".ssh_push_config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Removing existing SSH configuration file..."
    rm -f "$CONFIG_FILE"
    echo "✓ Removed existing SSH configuration"
else
    echo "✓ No existing SSH configuration found"
fi

# Clear shell command cache
if command -v hash &> /dev/null; then
    hash -r 2>/dev/null || true
    echo "✓ Cleared command cache"
fi

# Note: We don't modify system PATH files, so no cleanup needed here

echo ""
echo "Cleanup complete! Ready for fresh installation." 