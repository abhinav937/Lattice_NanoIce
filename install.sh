#!/bin/bash

# iCESugar-nano FPGA Flash Tool - Installation Script
# This script installs all dependencies and sets up the flash command alias

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

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "ubuntu"
        elif command -v pacman &> /dev/null; then
            echo "arch"
        elif command -v dnf &> /dev/null; then
            echo "fedora"
        elif command -v yum &> /dev/null; then
            echo "centos"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Function to install dependencies based on OS
install_dependencies() {
    local os=$(detect_os)
    
    print_status "Detected OS: $os"
    
    case $os in
        "ubuntu"|"debian")
            print_status "Installing dependencies using apt..."
            sudo apt-get update
            sudo apt-get install -y \
                build-essential \
                cmake \
                git \
                python3 \
                python3-pip \
                libftdi1-dev \
                libusb-1.0-0-dev \
                pkg-config
            ;;
        "arch")
            print_status "Installing dependencies using pacman..."
            sudo pacman -Syu --noconfirm \
                base-devel \
                cmake \
                git \
                python \
                python-pip \
                libftdi \
                libusb \
                pkg-config
            ;;
        "fedora")
            print_status "Installing dependencies using dnf..."
            sudo dnf install -y \
                gcc \
                gcc-c++ \
                cmake \
                git \
                python3 \
                python3-pip \
                libftdi-devel \
                libusb1-devel \
                pkg-config
            ;;
        "centos")
            print_status "Installing dependencies using yum..."
            sudo yum install -y \
                gcc \
                gcc-c++ \
                cmake \
                git \
                python3 \
                python3-pip \
                libftdi-devel \
                libusb1-devel \
                pkg-config
            ;;
        "macos")
            print_status "Installing dependencies using Homebrew..."
            if ! command -v brew &> /dev/null; then
                print_error "Homebrew not found. Please install Homebrew first:"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            brew update
            brew install \
                cmake \
                git \
                python3 \
                libftdi \
                libusb \
                pkg-config
            ;;
        *)
            print_error "Unsupported OS: $os"
            print_warning "Please install the following packages manually:"
            echo "  - build-essential/cmake/gcc"
            echo "  - git"
            echo "  - python3"
            echo "  - libftdi1-dev"
            echo "  - libusb-1.0-0-dev"
            echo "  - pkg-config"
            exit 1
            ;;
    esac
}

# Function to install FPGA toolchain
install_fpga_toolchain() {
    print_status "Installing FPGA toolchain..."
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Clone and build yosys
    print_status "Building yosys..."
    git clone https://github.com/YosysHQ/yosys.git
    cd yosys
    make -j$(nproc)
    sudo make install
    cd ..
    
    # Clone and build nextpnr-ice40
    print_status "Building nextpnr-ice40..."
    git clone https://github.com/YosysHQ/nextpnr.git
    cd nextpnr
    cmake -DARCH=ice40 -DCMAKE_BUILD_TYPE=Release .
    make -j$(nproc)
    sudo make install
    cd ..
    
    # Clone and build icepack
    print_status "Building icepack..."
    git clone https://github.com/cliffordwolf/icestorm.git
    cd icestorm/icepack
    make -j$(nproc)
    sudo make install
    cd ../..
    
    # Clone and build icesprog
    print_status "Building icesprog..."
    cd icestorm/icesprog
    make -j$(nproc)
    sudo make install
    cd ../..
    
    # Clean up
    cd /
    rm -rf "$temp_dir"
    
    print_success "FPGA toolchain installed successfully"
}

# Function to setup flash command alias
setup_alias() {
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
    
    print_status "Setting up flash command alias in $shell_rc"
    
    # Create alias line
    local alias_line="alias flash='python3 $flash_script'"
    
    # Check if alias already exists
    if grep -q "alias flash=" "$shell_rc" 2>/dev/null; then
        print_warning "Flash alias already exists in $shell_rc"
        print_status "Updating existing alias..."
        # Remove existing alias line
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

# Function to setup USB permissions (Linux only)
setup_usb_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
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
            print_error "$tool is not found"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        print_success "All FPGA tools are installed correctly"
    else
        print_error "Missing tools: ${missing_tools[*]}"
        print_warning "Please run the installation script again"
        return 1
    fi
    
    # Test flash command
    if command -v flash &> /dev/null; then
        print_success "Flash command is available"
    else
        print_warning "Flash command not found. Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
    fi
}

# Main installation function
main() {
    echo "=========================================="
    echo "iCESugar-nano FPGA Flash Tool Installer"
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
    
    # Install dependencies
    install_dependencies
    
    # Install FPGA toolchain
    install_fpga_toolchain
    
    # Setup USB permissions
    setup_usb_permissions
    
    # Setup alias
    setup_alias
    
    # Verify installation
    verify_installation
    
    echo ""
    echo "=========================================="
    print_success "Installation completed successfully!"
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