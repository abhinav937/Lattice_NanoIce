#!/bin/bash

# iCESugar-nano FPGA Flash Tool - Curl Uninstaller
# This script can be run directly with: bash <(curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/curl_uninstall.sh)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "=========================================="
echo "iCESugar-nano FPGA Flash Tool - Curl Uninstaller"
echo "=========================================="
echo ""

# Check if git is available
if ! command -v git &> /dev/null; then
    print_error "Git is required but not installed"
    echo "Please install git first:"
    echo "  Ubuntu/Debian: sudo apt install git"
    echo "  macOS: brew install git"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
print_status "Using temporary directory: $TEMP_DIR"

# Clone the repository
print_status "Cloning Lattice_NanoIce repository..."
if git clone --depth 1 https://github.com/abhinav937/Lattice_NanoIce.git "$TEMP_DIR/Lattice_NanoIce"; then
    print_success "Repository cloned successfully"
else
    print_error "Failed to clone repository"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Change to the cloned directory
cd "$TEMP_DIR/Lattice_NanoIce"

# Run the uninstallation
print_status "Starting uninstallation..."
if bash uninstall.sh "$@"; then
    print_success "Uninstallation completed successfully!"
    print_warning "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    print_success "Uninstallation finished!"
else
    print_error "Uninstallation failed"
    print_warning "Temporary files kept in: $TEMP_DIR"
    print_warning "You can manually run: cd $TEMP_DIR/Lattice_NanoIce && bash uninstall.sh"
    exit 1
fi 