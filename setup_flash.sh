#!/bin/bash

# Simple setup script for iCESugar-nano FPGA Flash Tool
# This script only sets up the flash command alias without building tools

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

# Function to check if flash alias is already set up
check_flash_alias() {
    local script_path=$(realpath "$0")
    local project_dir=$(dirname "$script_path")
    local flash_script="$project_dir/flash_fpga.py"
    
    # Determine shell configuration file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_rc="$HOME/.bashrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    # Check if alias exists and points to the correct script
    if grep -q "alias flash=" "$shell_rc" 2>/dev/null; then
        local existing_alias=$(grep "alias flash=" "$shell_rc" | head -1)
        if [[ "$existing_alias" == *"$flash_script"* ]]; then
            return 0  # Alias exists and is correct
        fi
    fi
    
    return 1  # Alias doesn't exist or is incorrect
}

# Function to setup flash command alias
setup_alias() {
    local script_path=$(realpath "$0")
    local project_dir=$(dirname "$script_path")
    local flash_script="$project_dir/flash_fpga.py"
    
    # Check if alias is already properly set up
    if check_flash_alias; then
        print_success "Flash alias is already properly configured"
        return 0
    fi
    
    # Determine shell configuration file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_rc="$HOME/.bashrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    print_status "Setting up flash command alias in $shell_rc"
    
    # Create alias line
    local alias_line="alias flash='python3 $flash_script'"
    
    # Check if alias already exists (but incorrect)
    if grep -q "alias flash=" "$shell_rc" 2>/dev/null; then
        print_warning "Flash alias already exists in $shell_rc but points to different location"
        print_status "Updating existing alias..."
        # Remove existing alias line and comment
        sed -i.bak '/# iCESugar-nano FPGA Flash Tool alias/d' "$shell_rc"
        sed -i.bak '/alias flash=/d' "$shell_rc"
    fi
    
    # Add alias to shell configuration
    echo "" >> "$shell_rc"
    echo "# iCESugar-nano FPGA Flash Tool alias" >> "$shell_rc"
    echo "$alias_line" >> "$shell_rc"
    echo "" >> "$shell_rc"
    
    print_success "Flash alias added to $shell_rc"
    
    # Source the configuration file
    print_status "Sourcing $shell_rc..."
    if [[ "$SHELL" == *"zsh"* ]]; then
        source "$shell_rc"
    else
        source "$shell_rc"
    fi
    
    print_success "Flash command is now available as 'flash'"
}

# Function to check if USB permissions are already set up
check_usb_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        local udev_rules="/etc/udev/rules.d/99-icesugar-nano.rules"
        if [[ -f "$udev_rules" ]]; then
            # Check if the file contains the correct rules
            if grep -q "1d50.*602b" "$udev_rules" 2>/dev/null; then
                return 0  # USB permissions are already configured
            fi
        fi
    fi
    return 1  # USB permissions are not configured
}

# Function to setup USB permissions (Linux only)
setup_usb_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Check if USB permissions are already set up
        if check_usb_permissions; then
            print_success "USB permissions are already configured"
            return 0
        fi
        
        print_status "Setting up USB permissions..."
        
        # Create udev rules for iCESugar-nano
        local udev_rules="/etc/udev/rules.d/99-icesugar-nano.rules"
        sudo tee "$udev_rules" > /dev/null << EOF
# iCESugar-nano FPGA board
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="602b", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="602b", MODE="0666"
EOF
        
        # Reload udev rules
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        
        print_success "USB permissions configured"
    fi
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    local tools=("yosys" "nextpnr-ice40" "icepack" "icesprog")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_success "$tool is installed"
        else
            print_warning "$tool is not found"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        print_success "All FPGA tools are installed correctly"
    else
        print_warning "Missing tools: ${missing_tools[*]}"
        echo ""
        echo "To install missing tools:"
        echo "  Ubuntu/Debian: sudo apt install yosys nextpnr-ice40"
        echo "  Arch: sudo pacman -S yosys nextpnr-ice40"
        echo "  macOS: brew install yosys nextpnr-ice40"
        echo ""
        echo "Or download from:"
        echo "  https://github.com/YosysHQ/yosys/releases"
        echo "  https://github.com/YosysHQ/nextpnr/releases"
    fi
    
    # Test flash command
    if command -v flash &> /dev/null; then
        print_success "Flash command is available"
    else
        print_warning "Flash command not found. Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
    fi
}

# Main setup function
main() {
    echo "=========================================="
    echo "iCESugar-nano FPGA Flash Tool Setup"
    echo "=========================================="
    echo ""
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Setup USB permissions
    setup_usb_permissions
    
    # Setup alias
    setup_alias
    
    # Verify installation
    verify_installation
    
    echo ""
    echo "=========================================="
    print_success "Setup completed successfully!"
    echo "=========================================="
    echo ""
    echo "Usage examples:"
    echo "  flash top.v                    # Basic usage"
    echo "  flash top.v top.pcf --verbose  # With verbose output"
    echo "  flash top.v --clock 2          # Set clock to 12MHz"
    echo ""
    echo "For more information, see the README.md file"
    echo ""
    print_warning "Please restart your terminal or run:"
    echo "  source ~/.bashrc  # or ~/.zshrc"
}

# Run main function
main "$@" 