#!/bin/bash

# iCESugar-nano FPGA Flash Tool - Installation Script
# This script installs all dependencies and sets up the flash command alias

# Exit on any error (commented out for better error handling)
# set -e

# Disable debug output for clean display
# set -x

# =============================================================================
# CONFIGURATION
# =============================================================================

# Build configuration
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2
readonly BUILD_TIMEOUT=1800  # 30 minutes
readonly MAX_PARALLEL_JOBS=4
readonly MIN_MEMORY_MB=2048
readonly MIN_DISK_GB=2

# Tool versions and repositories
readonly YOSYS_REPO="https://github.com/YosysHQ/yosys.git"
readonly ICESTORM_REPO="https://github.com/cliffordwolf/icestorm.git"
readonly NEXTPNR_REPO="https://github.com/YosysHQ/nextpnr.git"
readonly ICESUGAR_REPO="https://github.com/wuxx/icesugar.git"

# USB device information
readonly USB_VENDOR_ID="1d50"
readonly USB_PRODUCT_ID="602b"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

TEMP_DIR=""
CURRENT_DIR=""
SHUTDOWN_REQUESTED=false
QUICK_INSTALL=false
VERBOSE_MODE=false

# =============================================================================
# COLOR OUTPUT FUNCTIONS
# =============================================================================

# Check if terminal supports colors
supports_colors() {
    [[ -t 1 ]] && [[ -n "$TERM" ]] && [[ "$TERM" != "dumb" ]]
}

# Colors for output
if supports_colors; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly NC=''
fi

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

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}$1${NC}"
}

print_debug() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a file exists
file_exists() {
    [[ -f "$1" ]]
}

# Function to check if a directory exists
dir_exists() {
    [[ -d "$1" ]]
}

# Function to get the number of CPU cores
get_cpu_count() {
    if command_exists nproc; then
        nproc
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sysctl -n hw.ncpu
    else
        echo 1
    fi
}

# Function to get available memory in MB
get_available_memory() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        vm_stat | awk '/free/ {gsub(/\./, "", $3); print $3 * 4096 / 1024 / 1024}' | head -1
    elif command_exists free; then
        free -m | awk 'NR==2{printf "%.0f", $7}'
    else
        echo 4096  # Default fallback
    fi
}

# Function to get available disk space in GB
get_available_disk() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        df . | awk 'NR==2{printf "%.1f", $4/1024/1024/1024}'
    else
        df . | awk 'NR==2{printf "%.1f", $4/1024/1024}'
    fi
}

# =============================================================================
# SYSTEM DETECTION
# =============================================================================

# Function to detect OS
detect_os() {
    # Hardcode to ubuntu for now, as user is likely on Ubuntu
    echo "ubuntu"
    # Original logic (commented out for debugging):
    # if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    #     if command_exists apt-get; then
    #         echo "ubuntu"
    #     elif command_exists pacman; then
    #         echo "arch"
    #     elif command_exists dnf; then
    #         echo "fedora"
    #     elif command_exists yum; then
    #         echo "centos"
    #     else
    #         echo "linux"
    #     fi
    # elif [[ "$OSTYPE" == "darwin"* ]]; then
    #     echo "macos"
    # else
    #     echo "unknown"
    # fi
}

# Function to detect Ubuntu version
detect_ubuntu_version() {
    if file_exists /etc/os-release; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            echo "$VERSION_ID"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================

# Function to check if a package is installed (Ubuntu/Debian)
check_package_apt() {
    dpkg -l "$1" >/dev/null 2>&1
}

# Function to check if a package is installed (Arch)
check_package_pacman() {
    pacman -Q "$1" >/dev/null 2>&1
}

# Function to check if a package is installed (Fedora/CentOS)
check_package_dnf() {
    rpm -q "$1" >/dev/null 2>&1
}

# Function to check if a package is installed (macOS)
check_package_brew() {
    brew list "$1" >/dev/null 2>&1
}

# Function to get package list for OS
get_package_list() {
    local os="$1"
    
    case "$os" in
        "ubuntu"|"debian")
            echo "build-essential cmake git python3 python3-pip libftdi1-dev libusb-1.0-0-dev pkg-config libboost-all-dev libeigen3-dev libqt5svg5-dev libreadline-dev tcl-dev libffi-dev bison flex libhidapi-dev"
            ;;
        "arch")
            echo "base-devel cmake git python python-pip libftdi libusb pkg-config boost eigen qt5-base qt5-svg readline tcl libffi bison flex hidapi"
            ;;
        "fedora")
            echo "gcc gcc-c++ cmake git python3 python3-pip libftdi-devel libusb1-devel pkg-config boost-devel eigen3-devel qt5-qtbase-devel qt5-qtsvg-devel readline-devel tcl-devel libffi-devel bison flex hidapi-devel"
            ;;
        "centos")
            echo "gcc gcc-c++ cmake git python3 python3-pip libftdi-devel libusb1-devel pkg-config boost-devel eigen3-devel qt5-qtbase-devel qt5-qtsvg-devel readline-devel tcl-devel libffi-devel bison flex hidapi-devel"
            ;;
        "macos")
            echo "cmake git python3 libftdi libusb pkg-config boost eigen qt5 readline tcl-tk libffi bison flex hidapi"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to install packages for OS
install_packages() {
    local os="$1"
    local packages="$2"
    
    print_status "Installing packages for $os: $packages"
    
    case "$os" in
        "ubuntu"|"debian")
            local ubuntu_version=$(detect_ubuntu_version)
            print_status "Detected Ubuntu version: $ubuntu_version"
            
            if ! command_exists apt-get; then
                print_error "apt-get not found. Please install apt-get or ensure you're on an Ubuntu/Debian system."
                exit 1
            fi
            
            if ! sudo apt-get update; then
                print_error "Failed to run 'apt-get update'. Check your network or package manager configuration."
                exit 1
            fi
            
            # Install Qt5 packages based on Ubuntu version
            if [[ "$ubuntu_version" == "24.04" ]] || [[ "$ubuntu_version" == "23.10" ]] || [[ "$ubuntu_version" == "23.04" ]]; then
                print_status "Using modern Qt5 packages for Ubuntu $ubuntu_version"
                if ! sudo apt-get install -y qtbase5-dev qttools5-dev; then
                    print_error "Failed to install Qt5 packages."
                    exit 1
                fi
            else
                print_status "Using legacy Qt5 packages for Ubuntu $ubuntu_version"
                sudo apt-get install -y qt5-default || true
            fi
            
            if ! sudo apt-get install -y $packages; then
                print_error "Failed to install packages: $packages"
                exit 1
            fi
            ;;
        "arch")
            if ! command_exists pacman; then
                print_error "pacman not found. Please ensure you're on an Arch-based system."
                exit 1
            fi
            if ! sudo pacman -Syu --noconfirm $packages; then
                print_error "Failed to install packages: $packages"
                exit 1
            fi
            ;;
        "fedora")
            if ! command_exists dnf; then
                print_error "dnf not found. Please ensure you're on a Fedora-based system."
                exit 1
            fi
            if ! sudo dnf install -y $packages; then
                print_error "Failed to install packages: $packages"
                exit 1
            fi
            ;;
        "centos")
            if ! command_exists yum; then
                print_error "yum not found. Please ensure you're on a CentOS-based system."
                exit 1
            fi
            if ! sudo yum install -y $packages; then
                print_error "Failed to install packages: $packages"
                exit 1
            fi
            ;;
        "macos")
            if ! command_exists brew; then
                print_error "Homebrew not found. Please install Homebrew first:"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            if ! brew update; then
                print_error "Failed to update Homebrew."
                exit 1
            fi
            if ! brew install $packages; then
                print_error "Failed to install packages: $packages"
                exit 1
            fi
            ;;
        *)
            print_error "Unsupported OS: $os"
            exit 1
            ;;
    esac
    print_success "Packages installed successfully"
}

# =============================================================================
# SYSTEM CHECKS
# =============================================================================

# Function to check system dependencies
check_system_dependencies() {
    local os=$(detect_os)
    local package_list=$(get_package_list "$os")
    local missing_packages=()
    
    print_status "Checking system dependencies for $os..."
    
    if [[ -z "$package_list" ]]; then
        print_error "No package list defined for OS: $os"
        return 1
    fi
    
    for pkg in $package_list; do
        case "$os" in
            "ubuntu"|"debian")
                if ! check_package_apt "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
            "arch")
                if ! check_package_pacman "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
            "fedora"|"centos")
                if ! check_package_dnf "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
            "macos")
                if ! check_package_brew "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
        esac
    done
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        print_success "All system dependencies are installed"
        return 0
    else
        print_status "Missing packages: ${missing_packages[*]}"
        return 1
    fi
}

# Function to check FPGA tools
check_fpga_tools() {
    local tools=("yosys" "nextpnr-ice40" "icepack" "icesprog")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
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

# Function to check system resources
check_system_resources() {
    print_status "Checking system resources..."
    
    # Check memory
    local mem_available=$(get_available_memory)
    if [[ $mem_available -lt $MIN_MEMORY_MB ]]; then
        print_warning "Low memory detected: ${mem_available}MB available (recommended: ${MIN_MEMORY_MB}MB)"
        return 1
    else
        print_success "Memory OK: ${mem_available}MB available"
    fi
    
    # Check disk space
    local disk_available=$(get_available_disk)
    local disk_gb=$(echo "$disk_available" | cut -d. -f1)
    if [[ $disk_gb -lt $MIN_DISK_GB ]]; then
        print_warning "Low disk space: ${disk_available}GB available (recommended: ${MIN_DISK_GB}GB)"
        return 1
    else
        print_success "Disk space OK: ${disk_available}GB available"
    fi
    
    return 0
}

# Function to get optimal number of parallel jobs
get_optimal_jobs() {
    local num_jobs=$(get_cpu_count)
    
    # Limit to maximum allowed
    if [[ $num_jobs -gt $MAX_PARALLEL_JOBS ]]; then
        num_jobs=$MAX_PARALLEL_JOBS
    fi
    
    # Check memory and reduce if needed
    local mem_available=$(get_available_memory)
    if [[ $mem_available -lt 4096 ]]; then  # Less than 4GB
        num_jobs=2
    elif [[ $mem_available -lt 8192 ]]; then  # Less than 8GB
        num_jobs=3
    fi
    
    echo $num_jobs
}

# =============================================================================
# COMMAND EXECUTION
# =============================================================================

# Function to retry a command with exponential backoff
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-$MAX_RETRIES}"
    local delay="${3:-$RETRY_DELAY}"
    local timeout="${4:-}"
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
            print_error "Operation cancelled by user"
            return 1
        fi
        
        print_debug "Attempt $attempt/$max_attempts: $cmd"
        
        # Execute command with optional timeout
        if [[ -n "$timeout" ]]; then
            if timeout "$timeout" bash -c "$cmd"; then
                print_success "Command succeeded on attempt $attempt"
                return 0
            else
                local exit_code=$?
                if [[ $exit_code -eq 124 ]]; then
                    print_error "Command timed out after ${timeout}s"
                else
                    print_warning "Command failed with exit code $exit_code"
                fi
            fi
        else
            if eval "$cmd"; then
                print_success "Command succeeded on attempt $attempt"
                return 0
            else
                print_warning "Command failed on attempt $attempt"
            fi
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            print_warning "Retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
            
            # Clean up git state before retry
            if [[ "$cmd" == *"git clone"* ]]; then
                print_status "Cleaning up git state before retry..."
                local repo_name=$(echo "$cmd" | grep -o 'git clone.*' | sed 's/git clone.*\/\([^.]*\)\.git.*/\1/')
                if [[ -d "$repo_name" ]]; then
                    rm -rf "$repo_name" 2>/dev/null || true
                fi
            fi
        else
            print_error "Command failed after $max_attempts attempts"
            return 1
        fi
        ((attempt++))
    done
}

# =============================================================================
# FPGA TOOLCHAIN INSTALLATION
# =============================================================================

# Function to build and install a tool
build_tool() {
    local tool_name="$1"
    local repo_url="$2"
    local build_dir="$3"
    local build_commands="$4"
    
    if command_exists "$tool_name"; then
        print_success "$tool_name is already installed, skipping build"
        return 0
    fi
    
    print_status "Building $tool_name..."
    
    # Clone repository
    print_debug "Cloning $repo_url to $build_dir"
    if ! retry_command "git clone $repo_url $build_dir" 3 2; then
        print_error "Failed to clone $tool_name repository"
        return 1
    fi
    
    cd "$build_dir"
    
    # Initialize submodules if they exist
    if file_exists .gitmodules; then
        print_debug "Initializing $tool_name submodules..."
        if ! retry_command "git submodule update --init --recursive" 3 3; then
            print_error "Failed to initialize $tool_name submodules"
            return 1
        fi
    fi
    
    # Execute build commands
    local num_jobs=$(get_optimal_jobs)
    print_status "Using $num_jobs parallel jobs for $tool_name compilation"
    
    # Replace placeholders in build commands
    local commands=$(echo "$build_commands" | sed "s/{JOBS}/$num_jobs/g")
    
    # Execute each build command
    while IFS= read -r cmd; do
        if [[ -n "$cmd" ]]; then
            if ! retry_command "$cmd" 2 5; then
                print_error "Failed to build $tool_name"
                return 1
            fi
        fi
    done <<< "$commands"
    
    cd ..
    print_success "$tool_name built and installed successfully"
}

# =============================================================================
# ICESPROG INSTALLATION FROM WUXX/ICESUGAR
# =============================================================================

install_icesprog_from_wuxx() {
    local repo_url="https://github.com/wuxx/icesugar.git"
    local repo_dir="icesugar-wuxx"
    local tool_dir="$repo_dir/tools/src"
    
    if command_exists icesprog; then
        print_success "icesprog is already installed, skipping build from wuxx/icesugar"
        return 0
    fi

    # Ensure hidapi dependency is installed
    print_status "Checking for hidapi dependency..."
    local os=$(detect_os)
    case "$os" in
        "ubuntu"|"debian")
            if ! dpkg -l | grep -q "libhidapi-dev"; then
                print_status "Installing libhidapi-dev..."
                sudo apt-get update && sudo apt-get install -y libhidapi-dev
            fi
            ;;
        "arch")
            if ! pacman -Q | grep -q "hidapi"; then
                print_status "Installing hidapi..."
                sudo pacman -S --noconfirm hidapi
            fi
            ;;
        "fedora"|"centos")
            if ! rpm -q | grep -q "hidapi-devel"; then
                print_status "Installing hidapi-devel..."
                if command_exists dnf; then
                    sudo dnf install -y hidapi-devel
                else
                    sudo yum install -y hidapi-devel
                fi
            fi
            ;;
        "macos")
            if ! brew list | grep -q "hidapi"; then
                print_status "Installing hidapi..."
                brew install hidapi
            fi
            ;;
    esac

    print_status "Cloning wuxx/icesugar repository for icesprog..."
    if [[ ! -d "$repo_dir" ]]; then
        if ! git clone --depth 1 "$repo_url" "$repo_dir"; then
            print_error "Failed to clone $repo_url"
            return 1
        fi
    else
        print_status "$repo_dir already exists, pulling latest changes..."
        (cd "$repo_dir" && git pull)
    fi

    print_status "Building icesprog from $tool_dir..."
    if [[ -d "$tool_dir" ]]; then
        (cd "$tool_dir" && make -j$(get_optimal_jobs) && sudo make install)
        if command_exists icesprog; then
            print_success "icesprog installed successfully from wuxx/icesugar"
        else
            print_error "icesprog build or install failed"
            return 1
        fi
    else
        print_error "tools/src directory not found in $repo_dir"
        return 1
    fi

    # Optional: Clean up
    print_status "Cleaning up cloned wuxx/icesugar repo..."
    rm -rf "$repo_dir"
}

# Function to install FPGA toolchain
install_fpga_toolchain() {
    print_status "Installing FPGA toolchain..."
    
    # Store current directory
    CURRENT_DIR=$(pwd)
    
    # Check system resources
    if ! check_system_resources; then
        print_warning "System resources are below recommended levels"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled due to insufficient resources"
            return 1
        fi
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    print_status "Using temporary directory: $TEMP_DIR"
    
    # Build yosys
    build_tool "yosys" "$YOSYS_REPO" "yosys" "make -j{JOBS}\nsudo make install"
    
    # Build icestorm (must be built before nextpnr)
    build_tool "icepack" "$ICESTORM_REPO" "icestorm" "make -j{JOBS}\nsudo make install"
    
    # Build nextpnr-ice40 (must be built after icestorm)
    build_tool "nextpnr-ice40" "$NEXTPNR_REPO" "nextpnr" "cmake . -B build -DARCH=ice40 -DCMAKE_BUILD_TYPE=Release\ncmake --build build -j{JOBS}\nsudo cmake --install build"
    # Build icesprog from wuxx/icesugar/tools
    install_icesprog_from_wuxx
    
    print_success "FPGA toolchain installation completed"
}

# =============================================================================
# ALIAS SETUP
# =============================================================================

# Function to get shell configuration file
get_shell_rc() {
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "$HOME/.bashrc"
    else
        echo "$HOME/.bashrc"
    fi
}

# Function to check if flash alias is already set up
check_flash_alias() {
    local script_path=$(realpath "$0")
    local project_dir=$(dirname "$script_path")
    local flash_script="$project_dir/flash_fpga.py"
    local shell_rc=$(get_shell_rc)
    
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
    local shell_rc=$(get_shell_rc)
    
    # Check if alias is already properly set up
    if check_flash_alias; then
        print_success "Flash alias is already properly configured"
        return 0
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
    source "$shell_rc"
    
    print_success "Flash command is now available as 'flash'"
}

# =============================================================================
# USB PERMISSIONS
# =============================================================================

# Function to check if USB permissions are already set up
check_usb_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        local udev_rules="/etc/udev/rules.d/99-icesugar-nano.rules"
        if file_exists "$udev_rules"; then
            # Check if the file contains the correct rules
            if grep -q "$USB_VENDOR_ID.*$USB_PRODUCT_ID" "$udev_rules" 2>/dev/null; then
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
SUBSYSTEM=="usb", ATTRS{idVendor}=="$USB_VENDOR_ID", ATTRS{idProduct}=="$USB_PRODUCT_ID", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="$USB_VENDOR_ID", ATTRS{idProduct}=="$USB_PRODUCT_ID", MODE="0666"
EOF
        
        # Reload udev rules
        if ! sudo udevadm control --reload-rules; then
            print_error "Failed to reload udev rules"
            return 1
        fi
        if ! sudo udevadm trigger; then
            print_error "Failed to trigger udev rules"
            return 1
        fi
        
        print_success "USB permissions configured"
    fi
}

# =============================================================================
# VERIFICATION
# =============================================================================

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    local tools=("yosys" "nextpnr-ice40" "icepack" "icesprog")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
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
    if command_exists flash; then
        print_success "Flash command is available"
    else
        print_warning "Flash command not found. Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
    fi
}

# =============================================================================
# CLEANUP AND SIGNAL HANDLING
# =============================================================================

# Function to cleanup on exit
cleanup_on_exit() {
    if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
        print_warning "Installation interrupted by user"
    fi
    
    if [[ -n "$TEMP_DIR" ]] && dir_exists "$TEMP_DIR"; then
        print_status "Cleaning up temporary directory..."
        cd /
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    if [[ -n "$CURRENT_DIR" ]] && dir_exists "$CURRENT_DIR"; then
        cd "$CURRENT_DIR"
    fi
}

# Function to handle signals
signal_handler() {
    SHUTDOWN_REQUESTED=true
    print_warning "Received interrupt signal, cleaning up..."
    cleanup_on_exit
    exit 1
}

# Register signal handlers
trap signal_handler INT TERM
trap cleanup_on_exit EXIT

# =============================================================================
# QUICK INSTALL OPTION
# =============================================================================

# Function to show quick installation option
show_quick_install() {
    echo ""
    print_header "=========================================="
    print_header "Quick Installation Option"
    print_header "=========================================="
    echo ""
    echo "The full installation builds FPGA tools from source and can take 30+ minutes."
    echo "For a faster setup, you can:"
    echo ""
    echo "1. Install FPGA tools using package managers:"
    echo "   Ubuntu/Debian: sudo apt install yosys nextpnr-ice40"
    echo "   Arch: sudo pacman -S yosys nextpnr-ice40"
    echo "   macOS: brew install yosys nextpnr-ice40"
    echo ""
    echo "2. Or download pre-built binaries from:"
    echo "   https://github.com/YosysHQ/yosys/releases"
    echo "   https://github.com/YosysHQ/nextpnr/releases"
    echo ""
    echo "3. Then run this script with --quick flag:"
    echo "   ./install.sh --quick"
    echo ""
    read -p "Do you want to continue with full installation (y) or exit (n)? " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting. Run './install.sh --quick' after installing tools manually."
        exit 0
    fi
}

# =============================================================================
# MAIN INSTALLATION FUNCTIONS
# =============================================================================

# Function to install system dependencies
install_dependencies() {
    local os=$(detect_os)
    print_status "Detected OS: $os"

    # Get the full package list
    local package_list=$(get_package_list "$os")
    if [[ -z "$package_list" ]]; then
        print_error "Unsupported OS: $os"
        print_warning "Please install the following packages manually:"
        echo "  - build-essential/cmake/gcc"
        echo "  - git"
        echo "  - python3"
        echo "  - libftdi1-dev"
        echo "  - libusb-1.0-0-dev"
        echo "  - pkg-config"
        exit 1
    fi

    # Find missing packages
    local missing_packages=()
    for pkg in $package_list; do
        case "$os" in
            "ubuntu"|"debian")
                if ! check_package_apt "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
            "arch")
                if ! check_package_pacman "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
            "fedora"|"centos")
                if ! check_package_dnf "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
            "macos")
                if ! check_package_brew "$pkg"; then
                    missing_packages+=("$pkg")
                fi
                ;;
        esac
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        print_success "All system dependencies are installed"
        return 0
    else
        print_status "Missing packages: ${missing_packages[*]}"
        if ! install_missing_packages "$os" "${missing_packages[@]}"; then
            print_error "Failed to install missing packages"
            exit 1
        fi
    fi

    # Verify installation
    local still_missing=()
    for pkg in $package_list; do
        case "$os" in
            "ubuntu"|"debian")
                if ! check_package_apt "$pkg"; then
                    still_missing+=("$pkg")
                fi
                ;;
            "arch")
                if ! check_package_pacman "$pkg"; then
                    still_missing+=("$pkg")
                fi
                ;;
            "fedora"|"centos")
                if ! check_package_dnf "$pkg"; then
                    still_missing+=("$pkg")
                fi
                ;;
            "macos")
                if ! check_package_brew "$pkg"; then
                    still_missing+=("$pkg")
                fi
                ;;
        esac
    done
    if [[ ${#still_missing[@]} -eq 0 ]]; then
        print_success "System dependencies installed successfully"
    else
        print_error "Failed to install all system dependencies: ${still_missing[*]}"
        return 1
    fi
}

# Function to install only missing packages for OS
install_missing_packages() {
    local os="$1"
    shift
    local missing_packages=("$@")
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        print_success "No missing packages to install."
        return 0
    fi
    print_status "Installing missing packages: ${missing_packages[*]}"
    case "$os" in
        "ubuntu"|"debian")
            local ubuntu_version=$(detect_ubuntu_version)
            print_status "Detected Ubuntu version: $ubuntu_version"
            if ! command_exists apt-get; then
                print_error "apt-get not found. Please install apt-get or ensure you're on an Ubuntu/Debian system."
                return 1
            fi
            if ! sudo apt-get update; then
                print_error "Failed to run 'apt-get update'. Check your network or package manager configuration."
                return 1
            fi
            # Install Qt5 packages based on Ubuntu version
            if [[ "$ubuntu_version" == "24.04" ]] || [[ "$ubuntu_version" == "23.10" ]] || [[ "$ubuntu_version" == "23.04" ]]; then
                if [[ " ${missing_packages[*]} " =~ " qtbase5-dev " ]] || [[ " ${missing_packages[*]} " =~ " qttools5-dev " ]]; then
                    print_status "Using modern Qt5 packages for Ubuntu $ubuntu_version"
                    if ! sudo apt-get install -y qtbase5-dev qttools5-dev; then
                        print_error "Failed to install Qt5 packages"
                        return 1
                    fi
                fi
            else
                if [[ " ${missing_packages[*]} " =~ " qt5-default " ]]; then
                    print_status "Using legacy Qt5 packages for Ubuntu $ubuntu_version"
                    sudo apt-get install -y qt5-default || true
                fi
            fi
            if ! sudo apt-get install -y "${missing_packages[@]}"; then
                print_error "Failed to install packages: ${missing_packages[*]}"
                return 1
            fi
            ;;
        "arch")
            if ! sudo pacman -Syu --noconfirm "${missing_packages[@]}"; then
                print_error "Failed to install packages: ${missing_packages[*]}"
                return 1
            fi
            ;;
        "fedora")
            if ! sudo dnf install -y "${missing_packages[@]}"; then
                print_error "Failed to install packages: ${missing_packages[*]}"
                return 1
            fi
            ;;
        "centos")
            if ! sudo yum install -y "${missing_packages[@]}"; then
                print_error "Failed to install packages: ${missing_packages[*]}"
                return 1
            fi
            ;;
        "macos")
            if ! command_exists brew; then
                print_error "Homebrew not found. Please install Homebrew first:"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            if ! brew update; then
                print_error "Failed to update Homebrew"
                return 1
            fi
            if ! brew install "${missing_packages[@]}"; then
                print_error "Failed to install packages: ${missing_packages[*]}"
                return 1
            fi
            ;;
        *)
            print_error "Unsupported OS: $os"
            return 1
            ;;
    esac
}

# Function to show installation progress
show_progress() {
    local step="$1"
    local total_steps="$2"
    local description="$3"
    local percentage=$((step * 100 / total_steps))
    print_progress "Step $step/$total_steps ($percentage%) - $description"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --quick     Quick install mode (skip FPGA toolchain build)"
    echo "  --verbose   Enable verbose output"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full installation"
    echo "  $0 --quick           # Quick installation"
    echo "  $0 --verbose         # Verbose output"
    echo "  $0 --quick --verbose # Quick install with verbose output"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                QUICK_INSTALL=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            --help|-h)
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
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    print_header "=========================================="
    print_header "iCESugar-nano FPGA Flash Tool Installer"
    print_header "=========================================="
    echo ""
    
    # Show quick install option if not already selected
    if [[ "$QUICK_INSTALL" == "false" ]]; then
        show_quick_install
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command_exists python3; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check system requirements
    print_status "Checking system requirements..."
    check_system_resources || print_warning "System resources are below recommended levels"
    
    print_status "System requirements check completed, proceeding with installation..."
    
    # Determine total steps
    local total_steps=4
    local current_step=0
    
    print_debug "Starting installation with $total_steps steps"
    
    # Step 1: Install dependencies
    ((current_step++))
    show_progress $current_step $total_steps "Installing system dependencies"
    print_status "Starting dependency installation..."
    if ! install_dependencies; then
        print_error "Dependency installation failed"
        exit 1
    fi
    print_status "Dependency installation completed"
    
    # Step 2: Install FPGA toolchain based on mode
    if [[ "$QUICK_INSTALL" == "true" ]]; then
        ((current_step++))
        show_progress $current_step $total_steps "Quick install mode - skipping FPGA toolchain build"
        print_status "Please ensure yosys, nextpnr-ice40, icepack, and icesprog are installed"
        print_status "Quick install mode completed"
    else
        ((current_step++))
        show_progress $current_step $total_steps "Installing FPGA toolchain (this may take 30+ minutes)"
        print_status "Starting FPGA toolchain installation..."
        if ! install_fpga_toolchain; then
            print_error "FPGA toolchain installation failed"
            exit 1
        fi
        print_status "FPGA toolchain installation completed"
    fi
    
    # Step 3: Setup USB permissions
    ((current_step++))
    show_progress $current_step $total_steps "Setting up USB permissions"
    print_status "Starting USB permissions setup..."
    if ! setup_usb_permissions; then
        print_error "USB permissions setup failed"
        exit 1
    fi
    print_status "USB permissions setup completed"
    
    # Step 4: Setup flash command alias
    ((current_step++))
    show_progress $current_step $total_steps "Setting up flash command alias"
    print_status "Starting alias setup..."
    if ! setup_alias; then
        print_error "Alias setup failed"
        exit 1
    fi
    print_status "Alias setup completed"
    
    # Verify installation
    print_status "Verifying installation..."
    if ! verify_installation; then
        print_error "Installation verification failed"
        exit 1
    fi
    
    echo ""
    print_header "=========================================="
    print_success "Installation completed successfully!"
    print_header "=========================================="
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