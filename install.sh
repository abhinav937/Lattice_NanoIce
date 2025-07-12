#!/bin/bash

# iCESugar-nano FPGA Flash Tool - Simple Installation Script
# This script installs all dependencies and sets up the flash command

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root"
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    print_error "Python 3 is required but not installed"
    exit 1
fi

# Store original directory
ORIGINAL_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_status "Starting iCESugar-nano FPGA Flash Tool installation..."

# Function to detect OS and install packages
install_dependencies() {
    print_status "Installing system dependencies..."
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS="$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    
    case "$OS" in
        "ubuntu"|"debian")
            print_status "Detected Ubuntu/Debian system"
            sudo apt-get update
            sudo apt-get install -y build-essential cmake git python3 python3-pip \
                libftdi1-dev libusb-1.0-0-dev pkg-config libboost-all-dev \
                libeigen3-dev libqt5svg5-dev libreadline-dev tcl-dev libffi-dev \
                bison flex libhidapi-dev qtbase5-dev qttools5-dev
            ;;
        "arch")
            print_status "Detected Arch Linux system"
            sudo pacman -Syu --noconfirm base-devel cmake git python python-pip \
                libftdi libusb pkg-config boost eigen qt5-base qt5-svg readline \
                tcl libffi bison flex hidapi
            ;;
        "fedora")
            print_status "Detected Fedora system"
            sudo dnf install -y gcc gcc-c++ cmake git python3 python3-pip \
                libftdi-devel libusb1-devel pkg-config boost-devel eigen3-devel \
                qt5-qtbase-devel qt5-qtsvg-devel readline-devel tcl-devel \
                libffi-devel bison flex hidapi-devel
            ;;
        "macos")
            print_status "Detected macOS system"
            if ! command -v brew >/dev/null 2>&1; then
                print_error "Homebrew is required. Install it first:"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            brew update
            brew install cmake git python3 libftdi libusb pkg-config boost eigen qt5 readline tcl-tk libffi bison flex hidapi
            ;;
        *)
            print_warning "Unknown OS: $OS"
            print_status "Please install the following packages manually:"
            echo "  - build-essential/cmake/gcc"
            echo "  - git"
            echo "  - python3"
            echo "  - libftdi1-dev"
            echo "  - libusb-1.0-0-dev"
            echo "  - pkg-config"
            echo "  - libboost-all-dev"
            echo "  - libeigen3-dev"
            echo "  - qt5 development packages"
            echo "  - libhidapi-dev"
            ;;
    esac
    
    print_success "System dependencies installed"
}

# Function to install FPGA tools
install_fpga_tools() {
    print_status "Installing FPGA tools..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Function to build a tool
    build_tool() {
        local name="$1"
        local repo="$2"
        local build_cmd="$3"
        
        print_status "Building $name..."
        
        # Check if already installed
        if command -v "$name" >/dev/null 2>&1; then
            print_success "$name is already installed"
            return 0
        fi
        
        # Clone repository
        git clone --depth 1 "$repo" "$name"
        cd "$name"
        
        # Initialize submodules if they exist
        if [[ -f .gitmodules ]]; then
            git submodule update --init --recursive
        fi
        
        # Build and install
        eval "$build_cmd"
        
        cd ..
        print_success "$name installed"
    }
    
    # Build tools in order
    build_tool "yosys" "https://github.com/YosysHQ/yosys.git" "make -j$(nproc) && sudo make install"
    build_tool "icepack" "https://github.com/cliffordwolf/icestorm.git" "make -j$(nproc) && sudo make install"
    build_tool "nextpnr-ice40" "https://github.com/YosysHQ/nextpnr.git" "cmake . -B build -DARCH=ice40 -DCMAKE_BUILD_TYPE=Release && cmake --build build -j$(nproc) && cd build && sudo make install"
    
    # Build icesprog from wuxx/icesugar
    print_status "Building icesprog..."
    if ! command -v icesprog >/dev/null 2>&1; then
        git clone --depth 1 "https://github.com/wuxx/icesugar.git" icesugar
        cd icesugar/tools/src
        make -j$(nproc)
        sudo cp icesprog /usr/local/bin/
        sudo chmod +x /usr/local/bin/icesprog
        cd "$TEMP_DIR"
        print_success "icesprog installed"
    else
        print_success "icesprog is already installed"
    fi
    
    # Clean up
    cd "$ORIGINAL_DIR"
    rm -rf "$TEMP_DIR"
    
    print_success "FPGA tools installed"
}

# Function to setup USB permissions
setup_usb_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        print_status "Setting up USB permissions..."
        
        # Create udev rules
        sudo tee /etc/udev/rules.d/99-icesugar-nano.rules > /dev/null << EOF
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

# Function to install flash tool
install_flash_tool() {
    print_status "Installing flash tool..."
    
    # Copy flash_fpga.py to system bin
    local flash_script="$SCRIPT_DIR/flash_fpga.py"
    if [[ ! -f "$flash_script" ]]; then
        print_error "flash_fpga.py not found in $SCRIPT_DIR"
        exit 1
    fi
    
    sudo cp "$flash_script" /usr/local/bin/flash_fpga
    sudo chmod +x /usr/local/bin/flash_fpga
    
    # Add shebang if not present
    if ! head -1 /usr/local/bin/flash_fpga | grep -q "^#!"; then
        sudo sed -i '1i#!/usr/bin/env python3' /usr/local/bin/flash_fpga
    fi
    
    print_success "Flash tool installed"
}

# Function to setup shell alias
setup_alias() {
    print_status "Setting up shell alias..."
    
    # Determine shell config file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    # Remove existing alias if present
    if grep -q "alias flash=" "$shell_rc" 2>/dev/null; then
        sed -i.bak '/# iCESugar-nano FPGA Flash Tool alias/d' "$shell_rc"
        sed -i.bak '/alias flash=/d' "$shell_rc"
    fi
    
    # Add new alias
    echo "" >> "$shell_rc"
    echo "# iCESugar-nano FPGA Flash Tool alias" >> "$shell_rc"
    echo "alias flash='flash_fpga'" >> "$shell_rc"
    echo "" >> "$shell_rc"
    
    print_success "Shell alias configured in $shell_rc"
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    local tools=("yosys" "nextpnr-ice40" "icepack" "icesprog" "flash_fpga")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_success "$tool is installed"
        else
            print_error "$tool is missing"
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        print_success "All tools are installed correctly"
        return 0
    else
        print_error "Missing tools: ${missing[*]}"
        return 1
    fi
}

# Main installation process
main() {
    print_status "Starting installation..."
    
    # Install system dependencies
    install_dependencies
    
    # Install FPGA tools
    install_fpga_tools
    
    # Setup USB permissions
    setup_usb_permissions
    
    # Install flash tool
    install_flash_tool
    
    # Setup shell alias
    setup_alias
    
    # Verify installation
    if verify_installation; then
        echo ""
        print_success "Installation completed successfully!"
        echo ""
        echo "Usage examples:"
        echo "  flash top.v                    # Basic usage"
        echo "  flash top.v top.pcf --verbose  # With verbose output"
        echo "  flash top.v --clock 2          # Set clock to 12MHz"
        echo ""
        print_warning "Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
    else
        print_error "Installation verification failed"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo ""
        echo "This script installs the iCESugar-nano FPGA Flash Tool and all dependencies."
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac