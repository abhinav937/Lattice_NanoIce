#!/bin/bash

# Script to install OSS CAD Suite using the latest build for the detected platform
# Downloads from: https://github.com/YosysHQ/oss-cad-suite-build/releases/latest
# Installs to ~/opt/oss-cad-suite
# Requires curl and tar (for non-Windows platforms)
# Version: 1.4.4 (with improved UI, timestamps, and corrected flash usage examples)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Helper functions with timestamps
print_status() { echo -e "${BLUE}[$(get_timestamp)] [INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[$(get_timestamp)] [SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[$(get_timestamp)] [WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[$(get_timestamp)] [ERROR]${NC} $1"; }
print_update() { echo -e "${CYAN}[$(get_timestamp)] [UPDATE]${NC} $1"; }
print_header() { echo -e "${PURPLE}${BOLD}$1${NC}"; }

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
      aarch64) PLATFORM="linux-arm64" ;;  # Linux kernel reports aarch64, releases use arm64
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



# Function to check for updates
check_for_updates() {
    print_status "Checking for updates..."
    
    local updates_found=false
    
    # Check for script self-updates (only when running via curl)
    if [[ -z "$SCRIPT_DIR" ]] || [[ "$SCRIPT_DIR" == "/tmp" ]]; then
        print_status "Checking for script updates..."
        local temp_script="/tmp/install_check.sh"
        local timestamp=$(date +%s)
        if curl -s -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/install.sh?t=$timestamp" 2>/dev/null; then
            # Compare with current script (if we can determine it)
            local current_script=""
            if [[ -n "$BASH_SOURCE" ]] && [[ -f "$BASH_SOURCE" ]]; then
                current_script="$BASH_SOURCE"
            elif [[ -f "/tmp/install.sh" ]]; then
                current_script="/tmp/install.sh"
            fi
            
            if [[ -n "$current_script" ]] && [[ -f "$current_script" ]]; then
                if ! cmp -s "$temp_script" "$current_script"; then
                    print_status "Script update available"
                    updates_found=true
                    # Download the updated script
                    if cp "$temp_script" "$current_script" 2>/dev/null; then
                        chmod +x "$current_script"
                        print_success "Script updated to latest version"
                    else
                        print_warning "Could not update script automatically"
                    fi
                else
                    print_success "Script is up to date"
                fi
            else
                print_status "Could not determine current script location for comparison"
            fi
            rm -f "$temp_script"
        else
            print_warning "Could not check for script updates"
        fi
    fi
    
    # Check OSS CAD Suite updates
    if [[ -d "$INSTALL_DIR" ]]; then
        # Get latest release tag from GitHub
        local latest_response=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest 2>/dev/null)
        local latest_tag=$(echo "$latest_response" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [[ -n "$latest_tag" ]]; then
            # Check current OSS CAD Suite version
            local current_version=""
            if [[ -f "$INSTALL_DIR/VERSION" ]]; then
                current_version=$(cat "$INSTALL_DIR/VERSION")
            fi
            
            # Normalize version formats for comparison
            local normalized_latest=$(echo "$latest_tag" | tr -d '-')
            local normalized_current=$(echo "$current_version" | tr -d '-')
            
            if [[ "$normalized_current" != "$normalized_latest" ]]; then
                print_update "OSS CAD Suite update available: $current_version → $latest_tag"
                updates_found=true
            else
                print_success "OSS CAD Suite is up to date ($latest_tag)"
            fi
        else
            print_warning "Could not fetch OSS CAD Suite version information"
        fi
    fi
    
    # Check flash tool updates
    local flash_script="$HOME/.local/bin/flash_fpga.py"
    if [[ -f "$flash_script" ]]; then
        local temp_script="/tmp/flash_fpga_check.py"
        local timestamp=$(date +%s)
        if curl -s -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/flash_fpga.py?t=$timestamp" 2>/dev/null; then
            if ! cmp -s "$temp_script" "$flash_script"; then
                print_update "Flash tool update available"
                updates_found=true
            else
                print_success "Flash tool is up to date"
            fi
            rm -f "$temp_script"
        else
            print_warning "Could not check flash tool updates"
        fi
    fi
    
    # Check icesprog updates (if installed)
    if command -v icesprog &> /dev/null; then
        local icesprog_path=$(which icesprog)
        local icesprog_version=$(icesprog --version 2>/dev/null | head -1 || echo "unknown")
        print_status "icesprog version: $icesprog_version"
        # Note: icesprog updates would require rebuilding from source
    fi
    
    if [[ "$updates_found" == "true" ]]; then
        return 0  # Updates needed
    else
        return 1  # No updates needed
    fi
}

# Function to update all components
update_all_components() {
    print_status "Updating all components..."
    
    local updates_performed=false
    
    # Update OSS CAD Suite if needed
    if [[ -d "$INSTALL_DIR" ]]; then
        local latest_response=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest 2>/dev/null)
        local latest_tag=$(echo "$latest_response" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [[ -n "$latest_tag" ]]; then
            local current_version=""
            if [[ -f "$INSTALL_DIR/VERSION" ]]; then
                current_version=$(cat "$INSTALL_DIR/VERSION")
            fi
            
            local normalized_latest=$(echo "$latest_tag" | tr -d '-')
            local normalized_current=$(echo "$current_version" | tr -d '-')
            
            if [[ "$normalized_current" != "$normalized_latest" ]]; then
                print_status "Updating OSS CAD Suite from $current_version to $latest_tag..."
                # The main installation logic will handle the download and installation
                updates_performed=true
            fi
        fi
    fi
    
    # Update flash tool
    if update_flash_tool; then
        updates_performed=true
    fi
    
    # Update icesprog if needed (rebuild from source)
    if command -v icesprog &> /dev/null; then
        print_status "Checking icesprog for updates..."
        # icesprog would need to be rebuilt from source for updates
        # This could be added here if needed
    fi
    
    if [[ "$updates_performed" == "true" ]]; then
        print_success "All available updates completed"
        return 0
    else
        print_status "No updates were needed"
        return 1
    fi
}

# Function to update flash tool
update_flash_tool() {
    print_status "Updating flash tool..."
    
    local flash_script=""
    
    # Check if we're running from a git repository (local installation)
    if [[ -f "$SCRIPT_DIR/flash_fpga.py" ]]; then
        flash_script="$SCRIPT_DIR/flash_fpga.py"
        print_status "Using local flash tool from repository"
        return 0
    else
        # We're running via curl, so we need to download/update the flash tool
        flash_script="$HOME/.local/bin/flash_fpga.py"
        mkdir -p "$(dirname "$flash_script")"
        
        local temp_script="/tmp/flash_fpga_new.py"
        
        # Download latest version with cache-busting
        local timestamp=$(date +%s)
        if curl -s -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/flash_fpga.py?t=$timestamp" 2>/dev/null; then
            # Check if files are different
            if [[ ! -f "$flash_script" ]] || ! cmp -s "$temp_script" "$flash_script"; then
                mv "$temp_script" "$flash_script"
                chmod +x "$flash_script"
                print_success "Flash tool updated to $flash_script"
                return 0
            else
                rm "$temp_script"
                print_status "Flash tool is already up to date"
                return 1
            fi
        else
            print_error "Failed to download flash tool update"
            rm -f "$temp_script"
            return 1
        fi
    fi
}

# Function to self-update the script
self_update_script() {
    # Only attempt self-update when running via curl (not from local repository)
    if [[ -z "$SCRIPT_DIR" ]] || [[ "$SCRIPT_DIR" == "/tmp" ]]; then
        print_status "Checking for script self-updates..."
        
        # Clear any local curl cache
        if command -v curl-config &> /dev/null; then
            local curl_cache_dir=$(curl-config --ca-path 2>/dev/null | sed 's|/ca-bundle.crt||')
            if [[ -n "$curl_cache_dir" ]] && [[ -d "$curl_cache_dir" ]]; then
                print_status "Clearing curl cache..."
                rm -rf "$curl_cache_dir"/* 2>/dev/null || true
            fi
        fi
        
        local temp_script="/tmp/install_self_update.sh"
        # Add cache-busting headers and timestamp to bypass caching
        local timestamp=$(date +%s)
        if [[ "${NO_CACHE:-false}" == "true" ]]; then
            print_status "Forcing cache bypass..."
        fi
        print_status "Downloading latest script version (timestamp: $timestamp)..."
        if curl -s -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/install.sh?t=$timestamp" 2>/dev/null; then
            # Extract version numbers for comparison
            local current_version=""
            local latest_version=""
            
            if [[ -n "$BASH_SOURCE" ]] && [[ -f "$BASH_SOURCE" ]]; then
                current_version=$(grep -o "Version: [0-9.]*" "$BASH_SOURCE" | cut -d' ' -f2)
            fi
            latest_version=$(grep -o "Version: [0-9.]*" "$temp_script" | cut -d' ' -f2)
            
            print_status "Current version: ${current_version:-unknown}, Latest version: ${latest_version:-unknown}"
            
            # Try to determine the current script location
            local current_script=""
            if [[ -n "$BASH_SOURCE" ]] && [[ -f "$BASH_SOURCE" ]]; then
                current_script="$BASH_SOURCE"
            elif [[ -f "/tmp/install.sh" ]]; then
                current_script="/tmp/install.sh"
            fi
            
            if [[ -n "$current_script" ]] && [[ -f "$current_script" ]]; then
                if ! cmp -s "$temp_script" "$current_script"; then
                    print_status "Script update available (current: ${current_version:-unknown}, latest: ${latest_version:-unknown}) - updating..."
                    if cp "$temp_script" "$current_script" 2>/dev/null; then
                        chmod +x "$current_script"
                        print_success "Script updated to version ${latest_version:-latest}"
                        # Re-execute the updated script
                        exec bash "$current_script" "$@"
                        exit 0
                    else
                        print_warning "Could not update script automatically"
                    fi
                else
                    print_success "Script is up to date (version: ${current_version:-unknown})"
                fi
            else
                print_status "Could not determine current script location for self-update"
            fi
            rm -f "$temp_script"
        else
            print_warning "Could not check for script self-updates"
        fi
    fi
}

# Function to setup flash tool
setup_flash_tool() {
    print_status "Setting up flash tool..."
    
    # Check if flash tool needs updating
    local flash_updated=false
    local flash_script="$HOME/.local/bin/flash_fpga.py"
    
    if [[ -f "$flash_script" ]]; then
        local temp_script="/tmp/flash_fpga_check.py"
        local timestamp=$(date +%s)
        if curl -s -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/flash_fpga.py?t=$timestamp" 2>/dev/null; then
            if ! cmp -s "$temp_script" "$flash_script"; then
                # Update flash tool
                mv "$temp_script" "$flash_script"
                chmod +x "$flash_script"
                print_update "Flash tool updated successfully"
                flash_updated=true
            else
                rm "$temp_script"
                print_success "Flash tool is up to date"
            fi
        else
            print_warning "Could not check flash tool updates"
        fi
    else
        # First time installation
        update_flash_tool
        flash_updated=true
    fi
    
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
    
    # Add flash alias - use the correct path based on installation method
    local flash_script=""
    if [[ -f "$SCRIPT_DIR/flash_fpga.py" ]]; then
        flash_script="$SCRIPT_DIR/flash_fpga.py"
    else
        flash_script="$HOME/.local/bin/flash_fpga.py"
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

# Function to verify flash_fpga.py requirements
verify_flash_requirements() {
    print_status "Verifying flash_fpga.py requirements..."
    
    # Source the OSS CAD Suite environment
    if [[ -f "$INSTALL_DIR/environment" ]]; then
        source "$INSTALL_DIR/environment"
    fi
    
    # Define required tools
    local required_tools=("yosys" "nextpnr-ice40" "icepack" "icesprog")
    local missing_tools=()
    
    # Check each required tool (only show missing ones)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    # If any tools are missing, try to install them
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Missing required tools: ${missing_tools[*]}"
        print_status "Installing missing tools..."
        
        # Try package manager installation for missing tools
        if install_from_package_manager; then
            # Re-check after installation
            source "$INSTALL_DIR/environment"
            local still_missing=()
            
            for tool in "${missing_tools[@]}"; do
                if ! command -v "$tool" &> /dev/null; then
                    still_missing+=("$tool")
                fi
            done
            
            if [[ ${#still_missing[@]} -gt 0 ]]; then
                print_error "Failed to install: ${still_missing[*]}"
                print_warning "Some tools may not be available. Flash operations may fail."
            else
                print_success "All missing tools installed successfully!"
            fi
        else
            print_error "Failed to install missing tools via package manager"
            print_warning "Flash operations may fail due to missing tools: ${missing_tools[*]}"
        fi
    else
        print_success "All flash_fpga.py requirements are satisfied!"
    fi
    
    # Test flash tool functionality
    local flash_script=""
    if [[ -f "$SCRIPT_DIR/flash_fpga.py" ]]; then
        flash_script="$SCRIPT_DIR/flash_fpga.py"
    else
        flash_script="$HOME/.local/bin/flash_fpga.py"
    fi
    
    if [[ -f "$flash_script" ]]; then
        if python3 "$flash_script" --help &> /dev/null; then
            print_success "Flash tool verification complete"
        else
            print_warning "Flash tool may have issues - test with: flash --help"
        fi
    else
        print_error "Flash tool not found at expected location"
    fi
}

# Note: icesprog is included in OSS CAD Suite, no separate installation needed

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
    # Self-update the script if running via curl
    self_update_script "$@"

    if [[ "${UPDATE_ONLY:-false}" == "true" ]]; then
        print_header "=== Lattice NanoIce Update Check ==="
        print_status "Checking for updates only..."
        
        # Check for OSS CAD Suite updates
        if [[ -d "$HOME/opt/oss-cad-suite" ]]; then
            check_for_updates
        else
            print_warning "OSS CAD Suite not installed. Run without --update-only to install."
        fi
        
        # Always update flash tool
        setup_flash_tool
        print_success "Update check complete!"
        return 0
    fi
    
    print_header "=== Lattice NanoIce Installation Script ==="
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
        print_status "OSS CAD Suite appears to be already installed at $INSTALL_DIR"
        echo "Checking if tools are available..."
        
        # Source the environment to check tools
        if [[ -f "$INSTALL_DIR/environment" ]]; then
            source "$INSTALL_DIR/environment"
        fi
        
        # Check if key tools are available
        local missing_tools=()
        
        # Check each tool individually and collect missing ones
        if ! command -v yosys &> /dev/null; then
            missing_tools+=("yosys")
        fi
        if ! command -v nextpnr-ice40 &> /dev/null; then
            missing_tools+=("nextpnr-ice40")
        fi
        if ! command -v icepack &> /dev/null; then
            missing_tools+=("icepack")
        fi
        if ! command -v icesprog &> /dev/null; then
            missing_tools+=("icesprog")
        fi
        
        if [[ ${#missing_tools[@]} -eq 0 ]]; then
            print_success "OSS CAD Suite tools are already available!"
        else
            print_warning "Missing tools: ${missing_tools[*]}"
            print_status "Installing missing tools..."
            
            # Try package manager installation for missing tools
            if install_from_package_manager; then
                # Re-check after installation
                source "$INSTALL_DIR/environment"
                local still_missing=()
                
                for tool in "${missing_tools[@]}"; do
                    if ! command -v "$tool" &> /dev/null; then
                        still_missing+=("$tool")
                    fi
                done
                
                if [[ ${#still_missing[@]} -gt 0 ]]; then
                    print_error "Failed to install: ${still_missing[*]}"
                    print_warning "Some tools may not be available. Flash operations may fail."
                else
                    print_success "All missing tools installed successfully!"
                fi
            else
                print_error "Failed to install missing tools via package manager"
                print_warning "Flash operations may fail due to missing tools: ${missing_tools[*]}"
            fi
        fi
            
            # Check for OSS CAD Suite updates specifically
            local oss_update_needed=false
            local flash_update_needed=false
            local updates_available=()
            
            # Check OSS CAD Suite version
            local latest_response=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest)
            local latest_tag=$(echo "$latest_response" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
            
            if [[ -n "$latest_tag" ]]; then
                local current_version=""
                if [[ -f "$INSTALL_DIR/VERSION" ]]; then
                    current_version=$(cat "$INSTALL_DIR/VERSION")
                fi
                
                local normalized_latest=$(echo "$latest_tag" | tr -d '-')
                local normalized_current=$(echo "$current_version" | tr -d '-')
                
                if [[ "$normalized_current" != "$normalized_latest" ]]; then
                    print_update "OSS CAD Suite update available: $current_version → $latest_tag"
                    oss_update_needed=true
                    updates_available+=("OSS CAD Suite")
                else
                    print_success "OSS CAD Suite is up to date ($latest_tag)"
                fi
            fi
            
            # Check flash tool updates
            local flash_script="$HOME/.local/bin/flash_fpga.py"
            if [[ -f "$flash_script" ]]; then
                local temp_script="/tmp/flash_fpga_check.py"
                local timestamp=$(date +%s)
                if curl -s -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/flash_fpga.py?t=$timestamp" 2>/dev/null; then
                    if ! cmp -s "$temp_script" "$flash_script"; then
                        print_update "Flash tool update available"
                        flash_update_needed=true
                        updates_available+=("Flash Tool")
                    else
                        print_success "Flash tool is up to date"
                    fi
                    rm -f "$temp_script"
                fi
            fi
            
            # Show summary of available updates
            if [[ ${#updates_available[@]} -gt 0 ]]; then
                echo ""
                print_update "Available updates:"
                for update in "${updates_available[@]}"; do
                    echo "  • $update"
                done
                echo ""
            fi
            
            # Always setup flash tool and USB permissions
            setup_flash_tool
            setup_usb_permissions
            
            # If no OSS CAD Suite update was needed and not forcing update, exit here
            if [[ "$oss_update_needed" == "false" ]] && [[ "${FORCE_UPDATE:-false}" != "true" ]]; then
                print_success "Installation complete! All tools are ready to use."
                echo ""
                print_warning "Please restart your terminal or run:"
                echo "  source ~/.bashrc  # or ~/.zshrc"
                return 0
            fi
            
            # If OSS CAD Suite update is needed or forced, continue with download and installation
            if [[ "$oss_update_needed" == "true" ]] || [[ "${FORCE_UPDATE:-false}" == "true" ]]; then
                print_status "Proceeding with OSS CAD Suite update..."
            else
                print_status "No OSS CAD Suite update needed, skipping download."
                return 0
            fi
        else
            print_warning "OSS CAD Suite directory exists but tools are not available. Reinstalling..."
        fi
    else
        print_status "OSS CAD Suite not found. Proceeding with fresh installation..."
    fi
    
    # Get latest release tag
    print_status "Fetching latest release tag..."
    LATEST_RESPONSE=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest 2>/dev/null)
    LATEST_TAG=$(echo "$LATEST_RESPONSE" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_TAG" ]; then
        print_error "Failed to fetch latest tag. Check your connection or GitHub API."
        exit 1
    fi

    # Display version information
    print_success "Latest OSS CAD Suite version: $LATEST_TAG"
    print_status "Platform: $PLATFORM ($OS/$ARCH)"

    # Construct URL
    DATE_NO_DASH=$(echo "$LATEST_TAG" | tr -d '-')
    URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$LATEST_TAG/oss-cad-suite-$PLATFORM-${DATE_NO_DASH}.$EXT"

    # Download the archive with better error checking
    print_status "Downloading OSS CAD Suite: $(basename "$URL")"
    
    # First, check if the URL is valid by doing a HEAD request
    if ! curl -I -s "$URL" 2>/dev/null | grep -q "200 OK"; then
        print_warning "Platform-specific release not found, checking alternatives..."
        
        # Try to find alternative platforms for ARM64
        if [[ "$PLATFORM" == "linux-arm64" ]]; then
            print_status "Checking for ARM64 compatibility..."
            print_status "Note: Linux kernel reports 'aarch64' but releases use 'arm64' naming"
            ALTERNATIVE_URLS=(
                "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$LATEST_TAG/oss-cad-suite-linux-arm64-${DATE_NO_DASH}.$EXT"
            )
            
            for alt_url in "${ALTERNATIVE_URLS[@]}"; do
                print_status "Checking: $(basename "$alt_url")"
                if curl -I -s "$alt_url" 2>/dev/null | grep -q "200 OK"; then
                    URL="$alt_url"
                    print_success "✓ Found compatible version: $(basename "$URL")"
                    break
                fi
            done
        fi
    fi
    
    # Download the file
    if ! curl -L -s -o "oss-cad-suite.$EXT" "$URL" 2>/dev/null; then
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
        
        # Note: OSS CAD Suite environment is not automatically added to shell configuration
        # Users can manually source it when needed: source $INSTALL_DIR/environment
        print_status "OSS CAD Suite environment is available at $INSTALL_DIR/environment"
        print_status "To use the tools, manually source the environment: source $INSTALL_DIR/environment"

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

        # icesprog is included in OSS CAD Suite, no separate installation needed
        print_status "icesprog is included in OSS CAD Suite"

        # Final verification of flash_fpga.py requirements
        verify_flash_requirements
        
        # Instructions for persistent setup
        if [[ "$oss_update_needed" == "true" ]]; then
            print_update "OSS CAD Suite updated successfully"
        fi
        echo "Installation complete! OSS CAD Suite is installed at $INSTALL_DIR."
        echo "Yosys, nextpnr, Project IceStorm tools, and icesprog are now available."
        echo ""
        
        # Setup flash tool
        setup_flash_tool
        
        # Setup USB permissions
        setup_usb_permissions
        
        echo ""
        print_header "Available Tools:"
        echo "  • yosys - Verilog synthesis"
        echo "  • nextpnr-ice40 - Place and route"
        echo "  • icepack - Bitstream generation"
        echo "  • icesprog - FPGA programming"
        echo "  • flash - Complete flash workflow"
        echo ""
        print_success "OSS CAD Suite environment is available for manual sourcing"
        print_warning "To use the tools in a new terminal, run:"
        echo "  source $INSTALL_DIR/environment"
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        print_header "=== Lattice NanoIce Installation Script ==="
        echo ""
        echo "Usage: bash <(curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/install.sh) [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --version        Show script version"
        echo "  --force-update   Force update even if tools are available"
        echo "  --update-only    Only update flash tool and check for updates"
        echo "  --no-cache       Force bypass all caching (useful if updates aren't detected)"
        echo ""
        echo "This script installs the OSS CAD Suite and sets up the iCESugar-nano FPGA Flash Tool."
        echo "It automatically checks for updates and updates the flash tool on each run."
        echo ""
        echo "Note: Use 'curl -s' to suppress download progress output."
        echo "If you're not seeing updates, try using --no-cache to force bypass caching."
        exit 0
        ;;
    --version)
        # For process substitution, we need to download the script to get its version
        temp_script="/tmp/version_check.sh"
        if curl -s -H "Cache-Control: no-cache" -o "$temp_script" "https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/install.sh" 2>/dev/null; then
            version=$(grep -o "Version: [0-9.]*" "$temp_script" | cut -d' ' -f2)
            rm -f "$temp_script"
        else
            # Fallback: try to read from current script if possible
            if [[ -f "$0" ]]; then
                version=$(grep -o "Version: [0-9.]*" "$0" | cut -d' ' -f2)
            fi
        fi
        echo "Lattice NanoIce Install Script version: ${version:-unknown}"
        exit 0
        ;;
    --force-update)
        FORCE_UPDATE=true
        main
        ;;
    --update-only)
        UPDATE_ONLY=true
        main
        ;;
    --no-cache)
        NO_CACHE=true
        main
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