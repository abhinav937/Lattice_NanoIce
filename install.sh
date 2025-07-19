#!/bin/bash

# Script to install OSS CAD Suite using the latest build for the detected platform
# Downloads from: https://github.com/YosysHQ/oss-cad-suite-build/releases/latest
# Installs to ~/opt/oss-cad-suite
# Requires curl and tar (for non-Windows platforms)

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

# Store original directory
ORIGINAL_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required tools
if ! command -v curl &> /dev/null; then
    echo "curl is required but not installed. Please install it."
    exit 1
fi
if ! command -v tar &> /dev/null; then
    echo "tar is required but not installed. Please install it."
    exit 1
fi

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$OS" in
  linux)
    case "$ARCH" in
      x86_64) PLATFORM="linux-x64" ;;
      aarch64) PLATFORM="linux-arm64" ;;
      riscv64) PLATFORM="linux-riscv64" ;;
      *) echo "Unsupported architecture for Linux: $ARCH"; exit 1 ;;
    esac
    EXT="tgz"
    ;;
  darwin)
    case "$ARCH" in
      x86_64) PLATFORM="darwin-x64" ;;
      arm64) PLATFORM="darwin-arm64" ;;
      *) echo "Unsupported architecture for macOS: $ARCH"; exit 1 ;;
    esac
    EXT="tgz"
    ;;
  freebsd)
    case "$ARCH" in
      amd64) PLATFORM="freebsd-x64" ;;
      *) echo "Unsupported architecture for FreeBSD: $ARCH"; exit 1 ;;
    esac
    EXT="tgz"
    ;;
  mingw* | msys* | cygwin*)
    if [ "$ARCH" != "x86_64" ]; then
      echo "Unsupported architecture for Windows: $ARCH"; exit 1
    fi
    PLATFORM="windows-x64"
    EXT="exe"
    ;;
  *)
    echo "Unsupported OS: $OS"; exit 1
    ;;
esac



# Function to setup flash tool
setup_flash_tool() {
    print_status "Setting up flash tool..."
    
    # Determine shell configuration file
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    # Remove existing flash alias if present
    if grep -q "alias flash=" "$shell_rc" 2>/dev/null; then
        sed -i.bak '/# iCESugar-nano FPGA Flash Tool alias/d' "$shell_rc"
        sed -i.bak '/alias flash=/d' "$shell_rc"
    fi
    
    # Add flash alias
    local flash_script="$SCRIPT_DIR/flash_fpga.py"
    echo "" >> "$shell_rc"
    echo "# iCESugar-nano FPGA Flash Tool alias" >> "$shell_rc"
    echo "alias flash='python3 $flash_script'" >> "$shell_rc"
    echo "" >> "$shell_rc"
    
    print_success "Flash tool configured in $shell_rc"
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



# Main installation function
main() {
    print_status "Starting OSS CAD Suite installation..."
    
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
    
    # Get latest release tag
    echo "Fetching latest release tag..."
    LATEST_RESPONSE=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest)
    LATEST_TAG=$(echo "$LATEST_RESPONSE" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_TAG" ]; then
        echo "Failed to fetch latest tag. Check your connection or GitHub API."
        exit 1
    fi

    # Construct URL
    DATE_NO_DASH=$(echo "$LATEST_TAG" | tr -d '-')
    URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$LATEST_TAG/oss-cad-suite-$PLATFORM-${DATE_NO_DASH}.$EXT"

    # Download the archive
    echo "Downloading OSS CAD Suite for $PLATFORM from $URL..."
    curl -L -o "oss-cad-suite.$EXT" "$URL"
    if [ $? -ne 0 ]; then
        echo "Download failed. Check the URL or your connection. Verify if the release asset exists on GitHub."
        exit 1
    fi

    # Create installation directory
    INSTALL_DIR="$HOME/opt/oss-cad-suite"
    mkdir -p "$INSTALL_DIR"

    if [ "$EXT" = "exe" ]; then
        # For Windows, move the exe to install dir and provide instructions
        mv "oss-cad-suite.$EXT" "$INSTALL_DIR/oss-cad-suite-$PLATFORM.exe"
        echo "Downloaded self-extracting executable for Windows."
        echo "To install, navigate to $INSTALL_DIR and run oss-cad-suite-$PLATFORM.exe"
        echo "Follow the on-screen instructions for installation."
        echo "Note: Environment setup on Windows may involve adding to PATH manually or running a setup script provided by the suite."
        # Skip extraction, setup, and verification
    else
        # Extract the archive for other platforms
        echo "Extracting to $INSTALL_DIR..."
        tar -xzf "oss-cad-suite.$EXT" -C "$INSTALL_DIR" --strip-components=1
        if [ $? -ne 0 ]; then
            echo "Extraction failed."
            exit 1
        fi

        # Clean up
        rm "oss-cad-suite.$EXT"

        # Set up environment
        echo "Setting up environment..."
        source "$INSTALL_DIR/environment"

        # Verify installation of key tools: Yosys, nextpnr, and Project IceStorm (via icepack as an example)
        echo "Verifying tools..."
        if command -v yosys &> /dev/null; then
            echo "Yosys installed: $(yosys --version)"
        else
            echo "Yosys not found."
        fi

        if command -v nextpnr &> /dev/null; then
            echo "nextpnr installed: $(nextpnr --version)"
        else
            echo "nextpnr not found."
        fi

        if command -v icepack &> /dev/null; then
            echo "Project IceStorm installed (icepack available)."
        else
            echo "Project IceStorm tools (e.g., icepack) not found."
        fi

        # Install icesprog from iCESugar repository
        echo "Installing icesprog..."
        if ! command -v icesprog &> /dev/null; then
            # Create temporary directory for building icesprog
            TEMP_DIR=$(mktemp -d)
            cd "$TEMP_DIR"
            
            # Clone and build icesprog
            git clone --depth 1 "https://github.com/wuxx/icesugar.git" icesugar
            cd icesugar/tools/src
            make -j$(nproc)
            sudo cp icesprog /usr/local/bin/
            sudo chmod +x /usr/local/bin/icesprog
            
            # Clean up
            cd "$ORIGINAL_DIR"
            rm -rf "$TEMP_DIR"
            echo "icesprog installed successfully."
        else
            echo "icesprog is already installed."
        fi

        # Instructions for persistent setup
        echo "Installation complete! OSS CAD Suite is installed at $INSTALL_DIR."
        echo "Yosys, nextpnr, Project IceStorm tools, and icesprog are now available."
        echo ""
        
            # Setup flash tool
    setup_flash_tool
    
    # Setup USB permissions
    setup_usb_permissions
        
        echo ""
        echo "You can now use tools like yosys, nextpnr-ice40, icepack, icesprog, etc."
        echo ""
        echo "Usage examples:"
        echo "  flash top.v                    # Basic usage"
        echo "  flash top.v top.pcf --verbose  # With verbose output"
        echo "  flash top.v --clock 2          # Set clock to 12MHz"
        echo ""
        print_success "OSS CAD Suite environment is automatically sourced when needed"
        print_warning "Please restart your terminal or run:"
        echo "  source ~/.bashrc  # or ~/.zshrc"
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
        echo "This script installs the OSS CAD Suite and sets up the iCESugar-nano FPGA Flash Tool."
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