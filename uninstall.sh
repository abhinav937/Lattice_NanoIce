#!/bin/bash

# iCESugar-nano FPGA Flash Tool - Uninstall Script
# This script removes the flash command alias, OSS CAD Suite, and optionally removes FPGA tools

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to remove flash tool and alias
remove_flash_tool() {
    print_status "Removing flash tool..."
    
    # Remove the flash_fpga.py from ~/.local/bin (where install script puts it)
    local flash_script="$HOME/.local/bin/flash_fpga.py"
    if [[ -f "$flash_script" ]]; then
        if rm "$flash_script"; then
            print_success "Flash tool removed from $flash_script"
        else
            print_error "Failed to remove flash tool from $flash_script"
            return 1
        fi
    else
        print_warning "Flash tool not found at $flash_script"
    fi
    
    # Remove the ~/.local/bin directory if it's empty
    if [[ -d "$HOME/.local/bin" ]] && [[ -z "$(ls -A "$HOME/.local/bin")" ]]; then
        rmdir "$HOME/.local/bin"
        print_status "Removed empty ~/.local/bin directory"
    fi
    
    print_status "Removing flash command alias..."
    
    # Determine shell configuration file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_rc="$HOME/.bashrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    if [[ -f "$shell_rc" ]]; then
        # Remove flash alias lines
        if grep -q "alias flash=" "$shell_rc"; then
            # Create backup
            cp "$shell_rc" "$shell_rc.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Remove alias lines
            sed -i '/# iCESugar-nano FPGA Flash Tool alias/d' "$shell_rc"
            sed -i '/alias flash=/d' "$shell_rc"
            
            print_success "Flash alias removed from $shell_rc"
            print_warning "Backup created: $shell_rc.backup.*"
        else
            print_warning "Flash alias not found in $shell_rc"
        fi
    else
        print_warning "Shell configuration file not found: $shell_rc"
    fi
}

# Function to remove OSS CAD Suite
remove_oss_cad_suite() {
    print_status "Removing OSS CAD Suite..."
    
    local install_dir="$HOME/opt/oss-cad-suite"
    if [[ -d "$install_dir" ]]; then
        print_status "Found OSS CAD Suite at $install_dir"
        
        # Check if we have write permissions
        if [[ ! -w "$install_dir" ]]; then
            print_warning "No write permission to $install_dir"
            print_status "Attempting to change permissions..."
            if chmod -R u+w "$install_dir" 2>/dev/null; then
                print_success "Permissions changed successfully"
            else
                print_error "Failed to change permissions. You may need to run with sudo for this step."
                print_status "You can manually remove the directory with: sudo rm -rf $install_dir"
                return 1
            fi
        fi
        
        # Try to remove the directory
        print_status "Removing OSS CAD Suite files..."
        if rm -rf "$install_dir" 2>/dev/null; then
            print_success "OSS CAD Suite removed from $install_dir"
        else
            print_error "Failed to remove OSS CAD Suite from $install_dir"
            print_status "This might be due to permission issues or files being in use."
            print_status "You can try manually removing it with: sudo rm -rf $install_dir"
            return 1
        fi
    else
        print_warning "OSS CAD Suite not found at $install_dir"
    fi
    
    # Remove the ~/opt directory if it's empty
    if [[ -d "$HOME/opt" ]] && [[ -z "$(ls -A "$HOME/opt")" ]]; then
        if rmdir "$HOME/opt" 2>/dev/null; then
            print_status "Removed empty ~/opt directory"
        else
            print_warning "Could not remove ~/opt directory (may not be empty or have permission issues)"
        fi
    fi
}

# Function to remove USB permissions
remove_usb_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        print_status "Removing USB permissions..."
        
        local udev_rules="/etc/udev/rules.d/99-icesugar-nano.rules"
        if [[ -f "$udev_rules" ]]; then
            sudo rm "$udev_rules"
            sudo udevadm control --reload-rules
            sudo udevadm trigger
            print_success "USB permissions removed"
        else
            print_warning "USB permissions file not found"
        fi
    fi
}

# Function to remove package manager installed FPGA tools
remove_package_manager_tools() {
    print_status "Removing package manager installed FPGA tools..."
    
    # Try to remove via package manager (in case they were installed that way)
    if command -v apt-get &> /dev/null; then
        # Ubuntu/Debian - use || true to ignore errors if packages don't exist
        sudo apt-get remove -y yosys nextpnr-ice40 icepack 2>/dev/null || true
        sudo apt-get autoremove -y
        print_success "Removed via apt-get"
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -R --noconfirm yosys nextpnr-ice40 icepack 2>/dev/null || true
        print_success "Removed via pacman"
    elif command -v dnf &> /dev/null; then
        # Fedora
        sudo dnf remove -y yosys nextpnr-ice40 icepack 2>/dev/null || true
        print_success "Removed via dnf"
    elif command -v yum &> /dev/null; then
        # CentOS
        sudo yum remove -y yosys nextpnr-ice40 icepack 2>/dev/null || true
        print_success "Removed via yum"
    elif command -v brew &> /dev/null; then
        # macOS
        brew uninstall yosys nextpnr-ice40 icepack 2>/dev/null || true
        print_success "Removed via brew"
    else
        print_warning "Package manager not detected. Skipping package manager removal."
    fi
    
    # Remove system dependencies (optional)
    print_status "Removing system dependencies..."
    if command -v apt-get &> /dev/null; then
        # Ubuntu/Debian
        sudo apt-get remove -y libhidapi-dev libhidapi-hidraw-dev 2>/dev/null || true
        sudo apt-get autoremove -y
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -R --noconfirm hidapi 2>/dev/null || true
    elif command -v dnf &> /dev/null; then
        # Fedora
        sudo dnf remove -y hidapi-devel 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        # CentOS
        sudo yum remove -y hidapi-devel 2>/dev/null || true
    elif command -v brew &> /dev/null; then
        # macOS
        brew uninstall hidapi 2>/dev/null || true
    fi
    print_success "System dependencies removed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --flash-only     Remove only the flash tool and alias"
    echo "  --oss-only       Remove only the OSS CAD Suite"
    echo "  --tools-only     Remove only package manager installed FPGA tools"
    echo "  --all            Remove everything (default)"
    echo "  --force          Force removal without confirmation prompts"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0               # Remove everything (with confirmation)"
    echo "  $0 --force       # Remove everything without confirmation"
    echo "  $0 --flash-only  # Remove only flash tool and alias"
    echo "  $0 --oss-only    # Remove only OSS CAD Suite"
    echo "  $0 --tools-only  # Remove only package manager installed tools"
}

# Main function
main() {
    local remove_flash_flag=true
    local remove_oss_flag=true
    local remove_tools_flag=true
    local force_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --flash-only)
                remove_flash_flag=true
                remove_oss_flag=false
                remove_tools_flag=false
                shift
                ;;
            --oss-only)
                remove_flash_flag=false
                remove_oss_flag=true
                remove_tools_flag=false
                shift
                ;;
            --tools-only)
                remove_flash_flag=false
                remove_oss_flag=false
                remove_tools_flag=true
                shift
                ;;
            --all)
                remove_flash_flag=true
                remove_oss_flag=true
                remove_tools_flag=true
                shift
                ;;
            --force)
                force_flag=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "iCESugar-nano FPGA Flash Tool Uninstaller"
    echo "=========================================="
    echo ""
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi
    
    # Remove flash tool and alias
    if [[ "$remove_flash_flag" == true ]]; then
        remove_flash_tool
        remove_usb_permissions
    fi
    
    # Remove OSS CAD Suite
    if [[ "$remove_oss_flag" == true ]]; then
        echo ""
        print_warning "This will remove the OSS CAD Suite installation from ~/opt/oss-cad-suite"
        if [[ "$force_flag" == true ]]; then
            print_status "Force mode: proceeding without confirmation"
            if ! remove_oss_cad_suite; then
                echo ""
                print_warning "OSS CAD Suite removal failed. You can try:"
                echo "  sudo rm -rf ~/opt/oss-cad-suite"
                echo "  sudo rmdir ~/opt  # if empty"
            fi
        else
            read -p "Are you sure you want to continue? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if ! remove_oss_cad_suite; then
                    echo ""
                    print_warning "OSS CAD Suite removal failed. You can try:"
                    echo "  sudo rm -rf ~/opt/oss-cad-suite"
                    echo "  sudo rmdir ~/opt  # if empty"
                fi
            else
                print_status "Skipping OSS CAD Suite removal"
            fi
        fi
    fi
    
    # Remove package manager installed tools
    if [[ "$remove_tools_flag" == true ]]; then
        echo ""
        print_warning "This will remove package manager installed FPGA tools (yosys, nextpnr-ice40, icepack)"
        if [[ "$force_flag" == true ]]; then
            print_status "Force mode: proceeding without confirmation"
            remove_package_manager_tools
        else
            read -p "Are you sure you want to continue? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                remove_package_manager_tools
            else
                print_status "Skipping package manager tools removal"
            fi
        fi
    fi
    
    echo ""
    echo "=========================================="
    print_success "Uninstallation completed!"
    echo "=========================================="
    echo ""
    
    if [[ "$remove_flash_flag" == true ]]; then
        print_warning "Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
    fi
}

# Run main function
main "$@" 