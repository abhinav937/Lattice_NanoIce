#!/bin/bash
# SSH Push Tool Uninstall Script

set -e

echo "SSH Push Tool Uninstallation"
echo "============================"

# Remove ssh-push from /usr/local/bin/
if [[ -f "/usr/local/bin/ssh-push" ]]; then
    echo "Removing ssh-push from /usr/local/bin/..."
    sudo rm -f /usr/local/bin/ssh-push
    echo "✓ ssh-push removed from /usr/local/bin/"
else
    echo "✓ ssh-push not found in /usr/local/bin/"
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
            echo "  Backup saved as $config_file.backup.$(date +%Y%m%d_%H%M%S)"
        else
            echo "✓ No PATH entries found in $config_file"
        fi
    fi
done

# Remove configuration file if it exists
CONFIG_FILE="$HOME/.ssh_push_config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Removing SSH configuration file..."
    rm -f "$CONFIG_FILE"
    echo "✓ SSH configuration file removed"
else
    echo "✓ No SSH configuration file found"
fi

echo ""
echo "Uninstallation complete!"
echo ""
echo "Note: If you have any active terminal sessions, you may need to restart them"
echo "      for PATH changes to take effect." 