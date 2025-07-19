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
    local flash_script=""
    
    # Check if we're running from a git repository (local installation)
    if [[ -f "$SCRIPT_DIR/flash_fpga.py" ]]; then
        flash_script="$SCRIPT_DIR/flash_fpga.py"
    else
        # We're running via curl, so we need to download the flash tool
        print_status "Downloading flash tool..."
        flash_script="$HOME/.local/bin/flash_fpga.py"
        mkdir -p "$(dirname "$flash_script")"
        
        # Download flash_fpga.py from the repository
        if curl -s -o "$flash_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/flash_fpga.py"; then
            chmod +x "$flash_script"
            print_success "Flash tool downloaded to $flash_script"
        else
            print_error "Failed to download flash tool"
            return 1
        fi
    fi
    
    echo "" >> "$shell_rc"
    echo "# iCESugar-nano FPGA Flash Tool alias" >> "$shell_rc"
    echo "alias flash='python3 $flash_script'" >> "$shell_rc"
    echo "" >> "$shell_rc"
    
    print_success "Flash tool configured in $shell_rc"
}

# Function to install from package manager
install_from_package_manager() {
    print_status "Attempting to install FPGA tools from package manager..."
    
    # Detect package manager and install tools
    if command -v apt-get &> /dev/null; then
        # Ubuntu/Debian
        print_status "Using apt-get (Ubuntu/Debian)"
        sudo apt-get update
        sudo apt-get install -y yosys nextpnr-ice40 icepack
        if [[ $? -eq 0 ]]; then
            print_success "FPGA tools installed via apt-get"
            return 0
        fi
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        print_status "Using pacman (Arch Linux)"
        sudo pacman -S --noconfirm yosys nextpnr-ice40 icepack
        if [[ $? -eq 0 ]]; then
            print_success "FPGA tools installed via pacman"
            return 0
        fi
    elif command -v dnf &> /dev/null; then
        # Fedora
        print_status "Using dnf (Fedora)"
        sudo dnf install -y yosys nextpnr-ice40 icepack
        if [[ $? -eq 0 ]]; then
            print_success "FPGA tools installed via dnf"
            return 0
        fi
    elif command -v yum &> /dev/null; then
        # CentOS
        print_status "Using yum (CentOS)"
        sudo yum install -y yosys nextpnr-ice40 icepack
        if [[ $? -eq 0 ]]; then
            print_success "FPGA tools installed via yum"
            return 0
        fi
    elif command -v brew &> /dev/null; then
        # macOS
        print_status "Using brew (macOS)"
        brew install yosys nextpnr-ice40 icepack
        if [[ $? -eq 0 ]]; then
            print_success "FPGA tools installed via brew"
            return 0
        fi
    fi
    
    print_error "No supported package manager found or installation failed"
    return 1
}

# Function to install icesprog
install_icesprog() {
    if ! command -v icesprog &> /dev/null; then
        print_status "Installing icesprog..."
        
        # Check if git is available
        if ! command -v git &> /dev/null; then
            print_error "git is required to install icesprog"
            return 1
        fi
        
        # Check if make is available
        if ! command -v make &> /dev/null; then
            print_error "make is required to install icesprog"
            return 1
        fi
        
        # Create temporary directory for building icesprog
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        # Clone and build icesprog
        if git clone --depth 1 "https://github.com/wuxx/icesugar.git" icesugar; then
            cd icesugar/tools/src
            if make -j$(nproc); then
                sudo cp icesprog /usr/local/bin/
                sudo chmod +x /usr/local/bin/icesprog
                print_success "icesprog installed successfully."
            else
                print_error "Failed to build icesprog"
                cd "$ORIGINAL_DIR"
                rm -rf "$TEMP_DIR"
                return 1
            fi
        else
            print_error "Failed to clone icesugar repository"
            cd "$ORIGINAL_DIR"
            rm -rf "$TEMP_DIR"
            return 1
        fi
        
        # Clean up
        cd "$ORIGINAL_DIR"
        rm -rf "$TEMP_DIR"
    else
        print_status "icesprog is already installed."
    fi
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
    
    # Check if OSS CAD Suite is already installed
    INSTALL_DIR="$HOME/opt/oss-cad-suite"
    if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/environment" ]]; then
        print_warning "OSS CAD Suite appears to be already installed at $INSTALL_DIR"
        echo "Checking if tools are available..."
        
        # Source the environment to check tools
        if [[ -f "$INSTALL_DIR/environment" ]]; then
            source "$INSTALL_DIR/environment"
        fi
        
        # Check if key tools are available
        if command -v yosys &> /dev/null && command -v nextpnr-ice40 &> /dev/null && command -v icepack &> /dev/null; then
            print_success "OSS CAD Suite tools are already available!"
            echo "Yosys: $(yosys --version 2>/dev/null | head -1 || echo 'available')"
            echo "nextpnr-ice40: $(nextpnr-ice40 --version 2>/dev/null | head -1 || echo 'available')"
            echo "icepack: available"
            
            # Check if icesprog is available
            if command -v icesprog &> /dev/null; then
                echo "icesprog: available"
            else
                print_status "Installing icesprog..."
                install_icesprog
            fi
            
            # Setup flash tool and USB permissions
            setup_flash_tool
            setup_usb_permissions
            
            print_success "Installation complete! All tools are ready to use."
            echo ""
            echo "Usage examples:"
            echo "  flash top.v                    # Basic usage"
            echo "  flash top.v top.pcf --verbose  # With verbose output"
            echo "  flash top.v --clock 2          # Set clock to 12MHz"
            echo ""
            print_warning "Please restart your terminal or run:"
            echo "  source ~/.bashrc  # or ~/.zshrc"
            return 0
        else
            print_warning "OSS CAD Suite directory exists but tools are not available. Reinstalling..."
        fi
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

    # Download the archive with better error checking
    print_status "Downloading OSS CAD Suite: $(basename "$URL")"
    
    # First, check if the URL is valid by doing a HEAD request
    if ! curl -I -s "$URL" | grep -q "200 OK"; then
        print_warning "Platform-specific release not found, checking alternatives..."
        
        # Try to find alternative platforms for ARM64
        if [[ "$PLATFORM" == "linux-arm64" ]]; then
            print_status "Checking for ARM64 compatibility..."
            ALTERNATIVE_URLS=(
                "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$LATEST_TAG/oss-cad-suite-linux-aarch64-${DATE_NO_DASH}.$EXT"
                "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$LATEST_TAG/oss-cad-suite-linux-arm64-${DATE_NO_DASH}.$EXT"
            )
            
            for alt_url in "${ALTERNATIVE_URLS[@]}"; do
                print_status "Checking: $(basename "$alt_url")"
                if curl -I -s "$alt_url" | grep -q "200 OK"; then
                    URL="$alt_url"
                    print_success "✓ Found compatible version: $(basename "$URL")"
                    break
                fi
            done
        fi
    fi
    
    # Download the file
    if ! curl -L -o "oss-cad-suite.$EXT" "$URL"; then
        print_error "Download failed. Check the URL or your connection."
        print_error "URL attempted: $URL"
        print_error "This might be due to:"
        print_error "1. Network connectivity issues"
        print_error "2. GitHub API rate limiting"
        print_error "3. Release asset not available for this platform"
        exit 1
    fi
    
    # Check if downloaded file is valid (should be larger than 1MB for a real archive)
    if [[ ! -f "oss-cad-suite.$EXT" ]] || [[ ! -s "oss-cad-suite.$EXT" ]]; then
        print_error "Downloaded file is empty or invalid"
        rm -f "oss-cad-suite.$EXT"
        exit 1
    fi
    
    # Check file size (should be at least 1MB for a real archive)
    FILE_SIZE=$(stat -c%s "oss-cad-suite.$EXT" 2>/dev/null || stat -f%z "oss-cad-suite.$EXT" 2>/dev/null || echo "0")
    if [[ "$FILE_SIZE" -lt 1048576 ]]; then
        print_error "Downloaded file is too small ($FILE_SIZE bytes). This is likely an error page."
        print_error "Content preview:"
        head -5 "oss-cad-suite.$EXT" 2>/dev/null || echo "Could not read file"
        rm -f "oss-cad-suite.$EXT"
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
        if ! tar -xzf "oss-cad-suite.$EXT" -C "$INSTALL_DIR" --strip-components=1; then
                    print_error "Extraction failed. The downloaded file may be corrupted or not a valid archive."
        print_error "This could be due to:"
        print_error "1. Network interruption during download"
        print_error "2. GitHub returning an error page instead of the archive"
        print_error "3. Archive format not supported for this platform"
        rm -f "oss-cad-suite.$EXT"
        
        # Try package manager installation as fallback
        print_status "Trying package manager installation as fallback..."
        if install_from_package_manager; then
            print_success "Installation completed via package manager!"
            setup_flash_tool
            setup_usb_permissions
            return 0
        else
            print_error "All installation methods failed."
            exit 1
        fi
        fi

        # Clean up
        rm "oss-cad-suite.$EXT"

        # Set up environment
        echo "Setting up environment..."
        source "$INSTALL_DIR/environment"
        
        # Add OSS CAD Suite to shell configuration for persistent access
        print_status "Adding OSS CAD Suite to shell configuration..."
        if [[ "$SHELL" == *"zsh"* ]]; then
            shell_rc="$HOME/.zshrc"
        else
            shell_rc="$HOME/.bashrc"
        fi
        
        # Remove existing OSS CAD Suite source if present
        if grep -q "source.*oss-cad-suite.*environment" "$shell_rc" 2>/dev/null; then
            sed -i.bak '/# OSS CAD Suite environment/d' "$shell_rc"
            sed -i.bak '/source.*oss-cad-suite.*environment/d' "$shell_rc"
        fi
        
        # Add OSS CAD Suite environment source
        echo "" >> "$shell_rc"
        echo "# OSS CAD Suite environment" >> "$shell_rc"
        echo "source $INSTALL_DIR/environment" >> "$shell_rc"
        echo "" >> "$shell_rc"
        
        print_success "OSS CAD Suite environment added to $shell_rc"

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
        install_icesprog

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