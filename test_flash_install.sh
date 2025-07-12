#!/bin/bash

# Test script to verify flash executable installation

echo "Testing flash executable installation..."

# Source the install.sh to get the functions
source install.sh

# Test the flash executable installation
echo "Running install_flash_executable..."
if install_flash_executable; then
    echo "SUCCESS: flash_fpga installed as system executable"
    
    # Test if it's available
    if command_exists flash_fpga; then
        echo "SUCCESS: flash_fpga is available in PATH"
        which flash_fpga
        flash_fpga --help | head -5
    else
        echo "FAILED: flash_fpga not found in PATH"
        exit 1
    fi
else
    echo "FAILED: flash_fpga installation failed"
    exit 1
fi 