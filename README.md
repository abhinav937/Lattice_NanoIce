# iCESugar-nano FPGA Flash Tool

A comprehensive tool for synthesizing and programming iCESugar-nano FPGA boards.

## Quick Installation

### Option 1: One-Line Installation (Recommended)
```bash
bash <(curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/curl_install.sh)
```

### Option 2: Clone and Install (No chmod needed)
```bash
git clone https://github.com/abhinav937/Lattice_NanoIce.git
cd Lattice_NanoIce
bash install.sh
```

### Option 3: Direct Execution (After cloning)
```bash
git clone https://github.com/abhinav937/Lattice_NanoIce.git
cd Lattice_NanoIce
./install.sh
```

## Quick Uninstallation

### One-Line Uninstallation
```bash
bash <(curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/curl_uninstall.sh)
```

## Installation Options

- **Full Installation**: `bash install.sh` (builds all tools from source)
- **Quick Installation**: `bash install.sh --quick` (requires tools to be pre-installed)
- **Verbose Output**: `bash install.sh --verbose` (shows detailed progress)

## What Gets Installed

- **FPGA Tools**: yosys, nextpnr-ice40, icepack, icesprog
- **Flash Tool**: flash_fpga (system-wide executable)
- **USB Permissions**: udev rules for iCESugar-nano
- **Shell Alias**: `flash` command

## Usage

After installation, you can use the flash tool from anywhere:

```bash
# Basic usage
flash top.v

# With constraints file
flash top.v top.pcf

# Verbose output
flash top.v --verbose

# Set clock frequency
flash top.v --clock 2  # 12MHz
```

## Uninstallation

### Option 1: One-Line Uninstallation (Recommended)
```bash
bash <(curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/curl_uninstall.sh)
```

### Option 2: Manual Uninstallation
```bash
# Remove everything
./uninstall.sh

# Remove only flash tool
./uninstall.sh --alias-only

# Remove only FPGA tools
./uninstall.sh --tools-only
```

## Requirements

- Linux (Ubuntu/Debian/Arch/Fedora/CentOS) or macOS
- Python 3
- Git
- sudo access for installation

## Troubleshooting

If you encounter issues:

1. **Check system requirements**: Ensure you have sufficient disk space (2GB+) and memory (2GB+)
2. **Install dependencies manually**: Use your package manager to install build tools
3. **Run with verbose output**: `bash install.sh --verbose` for detailed error messages
4. **Check the logs**: Installation logs are saved to help diagnose issues

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.