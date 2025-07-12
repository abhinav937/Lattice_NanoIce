#!/bin/bash

# iCESugar-nano FPGA Flash Tool - Uninstall Script
# This script removes the flash command alias and optionally removes FPGA tools

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

# Function to remove flash executable and alias
remove_flash_tool() {
    print_status "Removing flash_fpga executable..."
    
    # Remove the flash_fpga executable
    if [[ -f "/usr/local/bin/flash_fpga" ]]; then
        if sudo rm "/usr/local/bin/flash_fpga"; then
            print_success "flash_fpga executable removed"
        else
            print_error "Failed to remove flash_fpga executable"
            return 1
        fi
    else
        print_warning "flash_fpga executable not found"
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

# Function to remove FPGA tools
remove_fpga_tools() {
    print_status "Removing FPGA tools..."
    
    # Remove manually installed tools first
    print_status "Removing manually installed tools..."
    
    # Remove icepack (built from source)
    if command -v icepack &> /dev/null; then
        local icepack_path=$(which icepack)
        if [[ -n "$icepack_path" ]]; then
            sudo rm -f "$icepack_path"
            print_success "icepack removed from $icepack_path"
        fi
    fi
    
    # Remove nextpnr-ice40 (built from source)
    if command -v nextpnr-ice40 &> /dev/null; then
        local nextpnr_path=$(which nextpnr-ice40)
        if [[ -n "$nextpnr_path" ]]; then
            sudo rm -f "$nextpnr_path"
            print_success "nextpnr-ice40 removed from $nextpnr_path"
        fi
    fi
    
    # Remove yosys (built from source)
    if command -v yosys &> /dev/null; then
        local yosys_path=$(which yosys)
        if [[ -n "$yosys_path" ]]; then
            sudo rm -f "$yosys_path"
            print_success "yosys removed from $yosys_path"
        fi
    fi
    
    # Try to remove via package manager (in case they were installed that way)
    print_status "Attempting to remove via package manager..."
    if command -v apt-get &> /dev/null; then
        # Ubuntu/Debian - use || true to ignore errors if packages don't exist
        sudo apt-get remove -y yosys nextpnr-ice40 icepack 2>/dev/null || true
        sudo apt-get autoremove -y
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -R --noconfirm yosys nextpnr-ice40 icepack 2>/dev/null || true
    elif command -v dnf &> /dev/null; then
        # Fedora
        sudo dnf remove -y yosys nextpnr-ice40 icepack 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        # CentOS
        sudo yum remove -y yosys nextpnr-ice40 icepack 2>/dev/null || true
    elif command -v brew &> /dev/null; then
        # macOS
        brew uninstall yosys nextpnr-ice40 icepack 2>/dev/null || true
    else
        print_warning "Package manager not detected. Manual removal completed."
    fi
    
    print_success "FPGA tools removal completed"
    
    # Remove manually installed icesprog
    print_status "Removing icesprog from wuxx/icesugar..."
    if command -v icesprog &> /dev/null; then
        # Find where icesprog is installed
        local icesprog_path=$(which icesprog)
        if [[ -n "$icesprog_path" ]]; then
            sudo rm -f "$icesprog_path"
            print_success "icesprog removed from $icesprog_path"
        fi
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
    echo "  --alias-only     Remove only the flash tool and alias"
    echo "  --tools-only     Remove only the FPGA tools and dependencies"
    echo "  --all            Remove everything (default)"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0               # Remove everything"
    echo "  $0 --alias-only  # Remove only flash_fpga executable and alias"
    echo "  $0 --tools-only  # Remove only FPGA tools and system dependencies"
}

# Main function
main() {
    local remove_alias_flag=true
    local remove_tools_flag=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --alias-only)
                remove_alias_flag=true
                remove_tools_flag=false
                shift
                ;;
            --tools-only)
                remove_alias_flag=false
                remove_tools_flag=true
                shift
                ;;
            --all)
                remove_alias_flag=true
                remove_tools_flag=true
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
    if [[ "$remove_alias_flag" == true ]]; then
        remove_flash_tool
    fi
    
    # Remove USB permissions
    if [[ "$remove_alias_flag" == true ]]; then
        remove_usb_permissions
    fi
    
    # Remove FPGA tools
    if [[ "$remove_tools_flag" == true ]]; then
        echo ""
        print_warning "This will remove the FPGA toolchain (yosys, nextpnr-ice40, icepack, icesprog from wuxx/icesugar)"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remove_fpga_tools
        else
            print_status "Skipping FPGA tools removal"
        fi
    fi
    
    echo ""
    echo "=========================================="
    print_success "Uninstallation completed!"
    echo "=========================================="
    echo ""
    
    if [[ "$remove_alias_flag" == true ]]; then
        print_warning "Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
    fi
}

# Run main function
main "$@" 