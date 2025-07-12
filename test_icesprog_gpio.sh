#!/bin/bash

echo "Testing icesprog GPIO commands..."

# Test 1: Help
echo "=== Test 1: Help ==="
icesprog --help 2>&1 | grep -i gpio || echo "No GPIO help found"

# Test 2: GPIO mode setting
echo "=== Test 2: GPIO mode setting ==="
echo "Command: icesprog -g PB6 -m 1"
icesprog -g PB6 -m 1 2>&1 || echo "Command failed (expected without device)"

# Test 3: GPIO read
echo "=== Test 3: GPIO read ==="
echo "Command: icesprog -r -g PB6"
icesprog -r -g PB6 2>&1 || echo "Command failed (expected without device)"

# Test 4: GPIO write
echo "=== Test 4: GPIO write ==="
echo "Command: icesprog -w -g PB6 1"
icesprog -w -g PB6 1 2>&1 || echo "Command failed (expected without device)"

# Test 5: Alternative command structure
echo "=== Test 5: Alternative structure ==="
echo "Command: icesprog -g PB6 -m 1"
icesprog -g PB6 -m 1 2>&1 || echo "Command failed (expected without device)"

echo "=== Test completed ===" 