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
    
    # Check if dependencies are already installed
    if check_system_dependencies; then
        print_status "Skipping system dependencies installation (already installed)"
        return 0
    fi
    
    case $os in
        "ubuntu"|"debian")
            print_status "Installing missing dependencies using apt..."
            sudo apt-get update
            sudo apt-get install -y \
                build-essential \
                cmake \
                git \
                python3 \
                python3-pip \
                libftdi1-dev \
                libusb-1.0-0-dev \
                pkg-config \
                libboost-all-dev \
                libeigen3-dev \
                qt5-default \
                libqt5svg5-dev \
                libreadline-dev \
                tcl-dev \
                libffi-dev \
                bison \
                flex
            ;;
        "arch")
            print_status "Installing missing dependencies using pacman..."
            sudo pacman -Syu --noconfirm \
                base-devel \
                cmake \
                git \
                python \
                python-pip \
                libftdi \
                libusb \
                pkg-config \
                boost \
                eigen \
                qt5-base \
                qt5-svg \
                readline \
                tcl \
                libffi \
                bison \
                flex
            ;;
        "fedora")
            print_status "Installing missing dependencies using dnf..."
            sudo dnf install -y \
                gcc \
                gcc-c++ \
                cmake \
                git \
                python3 \
                python3-pip \
                libftdi-devel \
                libusb1-devel \
                pkg-config \
                boost-devel \
                eigen3-devel \
                qt5-qtbase-devel \
                qt5-qtsvg-devel \
                readline-devel \
                tcl-devel \
                libffi-devel \
                bison \
                flex
            ;;
        "centos")
            print_status "Installing missing dependencies using yum..."
            sudo yum install -y \
                gcc \
                gcc-c++ \
                cmake \
                git \
                python3 \
                python3-pip \
                libftdi-devel \
                libusb1-devel \
                pkg-config \
                boost-devel \
                eigen3-devel \
                qt5-qtbase-devel \
                qt5-qtsvg-devel \
                readline-devel \
                tcl-devel \
                libffi-devel \
                bison \
                flex
            ;;
        "macos")
            print_status "Installing missing dependencies using Homebrew..."
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
                pkg-config \
                boost \
                eigen \
                qt5 \
                readline \
                tcl-tk \
                libffi \
                bison \
                flex
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
    
    # Verify installation
    if check_system_dependencies; then
        print_success "System dependencies installed successfully"
    else
        print_error "Failed to install all system dependencies"
        return 1
    fi
}

# Function to check if a package is installed (Ubuntu/Debian)
check_package_apt() {
    dpkg -l "$1" &> /dev/null
}

# Function to check if a package is installed (Arch)
check_package_pacman() {
    pacman -Q "$1" &> /dev/null
}

# Function to check if a package is installed (Fedora/CentOS)
check_package_dnf() {
    rpm -q "$1" &> /dev/null
}

# Function to check if a package is installed (macOS)
check_package_brew() {
    brew list "$1" &> /dev/null
}

# Function to check if FPGA tools are already installed
check_fpga_tools() {
    local tools=("yosys" "nextpnr-ice40" "icepack" "icesprog")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        print_success "All FPGA tools are already installed"
        return 0
    else
        print_status "Missing tools: ${missing_tools[*]}"
        return 1
    fi
}

# Function to check system dependencies
check_system_dependencies() {
    local os=$(detect_os)
    local missing_packages=()
    
    print_status "Checking system dependencies..."
    
    case $os in
        "ubuntu"|"debian")
            local packages=(
                "build-essential" "cmake" "git" "python3" "python3-pip"
                "libftdi1-dev" "libusb-1.0-0-dev" "pkg-config"
                "libboost-all-dev" "libeigen3-dev" "qt5-default"
                "libqt5svg5-dev" "libreadline-dev" "tcl-dev"
                "libffi-dev" "bison" "flex"
            )
            for pkg in "${packages[@]}"; do
                if ! check_package_apt "$pkg"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "arch")
            local packages=(
                "base-devel" "cmake" "git" "python" "python-pip"
                "libftdi" "libusb" "pkg-config" "boost" "eigen"
                "qt5-base" "qt5-svg" "readline" "tcl" "libffi"
                "bison" "flex"
            )
            for pkg in "${packages[@]}"; do
                if ! check_package_pacman "$pkg"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "fedora")
            local packages=(
                "gcc" "gcc-c++" "cmake" "git" "python3" "python3-pip"
                "libftdi-devel" "libusb1-devel" "pkg-config"
                "boost-devel" "eigen3-devel" "qt5-qtbase-devel"
                "qt5-qtsvg-devel" "readline-devel" "tcl-devel"
                "libffi-devel" "bison" "flex"
            )
            for pkg in "${packages[@]}"; do
                if ! check_package_dnf "$pkg"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "centos")
            local packages=(
                "gcc" "gcc-c++" "cmake" "git" "python3" "python3-pip"
                "libftdi-devel" "libusb1-devel" "pkg-config"
                "boost-devel" "eigen3-devel" "qt5-qtbase-devel"
                "qt5-qtsvg-devel" "readline-devel" "tcl-devel"
                "libffi-devel" "bison" "flex"
            )
            for pkg in "${packages[@]}"; do
                if ! check_package_dnf "$pkg"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "macos")
            local packages=(
                "cmake" "git" "python3" "libftdi" "libusb" "pkg-config"
                "boost" "eigen" "qt5" "readline" "tcl-tk" "libffi"
                "bison" "flex"
            )
            for pkg in "${packages[@]}"; do
                if ! check_package_brew "$pkg"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
    esac
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        print_success "All system dependencies are already installed"
        return 0
    else
        print_status "Missing system packages: ${missing_packages[*]}"
        return 1
    fi
}

# Function to install FPGA toolchain
install_fpga_toolchain() {
    print_status "Installing FPGA toolchain..."
    
    # Check if tools are already installed
    if check_fpga_tools; then
        print_status "Skipping FPGA toolchain installation (already installed)"
        return 0
    fi
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Clone and build yosys
    print_status "Building yosys..."
    if ! git clone https://github.com/YosysHQ/yosys.git; then
        print_error "Failed to clone yosys repository"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd yosys
    # Initialize and update git submodules
    print_status "Initializing yosys submodules..."
    if ! git submodule update --init --recursive; then
        print_error "Failed to initialize yosys submodules"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Compiling yosys..."
    if ! make -j$(nproc); then
        print_error "Failed to compile yosys"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! sudo make install; then
        print_error "Failed to install yosys"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    cd ..
    
    # Clone and build nextpnr-ice40
    print_status "Building nextpnr-ice40..."
    if ! git clone https://github.com/YosysHQ/nextpnr.git; then
        print_error "Failed to clone nextpnr repository"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd nextpnr
    # Initialize and update git submodules
    print_status "Initializing nextpnr submodules..."
    if ! git submodule update --init --recursive; then
        print_error "Failed to initialize nextpnr submodules"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Configuring nextpnr..."
    if ! cmake -DARCH=ice40 -DCMAKE_BUILD_TYPE=Release .; then
        print_error "Failed to configure nextpnr"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Compiling nextpnr..."
    if ! make -j$(nproc); then
        print_error "Failed to compile nextpnr"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! sudo make install; then
        print_error "Failed to install nextpnr"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    cd ..
    
    # Clone and build icepack
    print_status "Building icepack..."
    if ! git clone https://github.com/cliffordwolf/icestorm.git; then
        print_error "Failed to clone icestorm repository"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd icestorm/icepack
    print_status "Compiling icepack..."
    if ! make -j$(nproc); then
        print_error "Failed to compile icepack"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! sudo make install; then
        print_error "Failed to install icepack"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    cd ../..
    
    # Clone and build icesprog
    print_status "Building icesprog..."
    cd icestorm/icesprog
    print_status "Compiling icesprog..."
    if ! make -j$(nproc); then
        print_error "Failed to compile icesprog"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! sudo make install; then
        print_error "Failed to install icesprog"
        cd ../..
        rm -rf "$temp_dir"
        return 1
    fi
    cd ../..
    
    # Clean up
    cd /
    rm -rf "$temp_dir"
    
    print_success "FPGA toolchain installed successfully"
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