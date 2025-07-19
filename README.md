# iCESugar-nano FPGA Flash Tool

A comprehensive tool for synthesizing and programming iCESugar-nano FPGA boards. This tool provides a streamlined workflow for FPGA development, from Verilog synthesis to board programming.

## Features

- **One-Command Flash**: Synthesize and program your FPGA with a single command
- **Automatic Toolchain Setup**: Installs OSS CAD Suite with all required FPGA tools (yosys, nextpnr-ice40, icepack, icesprog)
- **Cross-Platform Support**: Works on Linux, macOS, and FreeBSD
- **Flexible Configuration**: Support for custom constraints and clock frequencies
- **Easy Installation**: Multiple installation options including one-line curl installation
- **Automatic Environment Management**: Flash tool automatically sources the OSS CAD Suite environment when needed
- **Smart Device Detection**: Automatic device status checking with clear connection feedback
- **Intelligent Error Handling**: User-friendly error messages and helpful suggestions
- **Board-Specific Validation**: Prevents use of Pro-only features on nano boards

## Quick Installation

### Option 1: One-Line Installation (Recommended)
```bash
curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/install.sh | bash
```

### Option 2: Clone and Install
```bash
git clone https://github.com/abhinav937/Lattice_NanoIce.git
cd Lattice_NanoIce
./install.sh
```

## Quick Uninstallation

### One-Line Uninstallation (with confirmation prompts)
```bash
curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/uninstall.sh | bash
```

### One-Line Uninstallation (force removal, no prompts)
```bash
curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/uninstall.sh | bash -s -- --force
```

## Installation Options

- **Full Installation**: `./install.sh` (installs OSS CAD Suite and sets up flash tool)
- **Update Only**: `./install.sh --update-only` (checks for updates and updates flash tool)
- **Force Update**: `./install.sh --force-update` (forces update even if tools are available)
- **No Cache**: `./install.sh --no-cache` (bypasses caching for updates)

## What Gets Installed

- **OSS CAD Suite**: Complete FPGA toolchain (yosys, nextpnr-ice40, icepack, icesprog) installed to `~/opt/oss-cad-suite`
- **Flash Tool**: `flash_fpga.py` installed to `~/.local/bin/flash_fpga.py`
- **Shell Alias**: `flash` command added to your shell configuration
- **USB Permissions**: udev rules for iCESugar-nano (Linux only)

## Environment Setup

The installation script installs the OSS CAD Suite to `~/opt/oss-cad-suite` but **does not automatically source it in your shell configuration**. This gives you full control over when the environment is loaded.

### Manual Environment Sourcing
When you need to use the FPGA tools directly (not through the flash tool), manually source the environment:
```bash
source ~/opt/oss-cad-suite/environment
```

### Automatic Environment Sourcing
The `flash` command automatically sources the OSS CAD Suite environment when needed, so you don't need to manually source it before running flash commands.

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
flash top.v -c 2  # 12MHz

# Build only (skip programming)
flash top.v --build-only

# Force drag-and-drop programming
flash top.v --force-dragdrop

# Show help
flash --help
```

## Supported Clock Frequencies

The tool supports various clock frequencies for the iCESugar-nano:
- `-c 1`: 8MHz
- `-c 2`: 12MHz (default)
- `-c 3`: 36MHz
- `-c 4`: 72MHz

## Advanced Usage

### GPIO Operations
```bash
# Read GPIO pin
flash -g PA5 --gpio-read

# Write to GPIO pin
flash -g PB3 --gpio-write --gpio-value 1

# Set GPIO mode
flash -g PC7 -m 1  # 1=output, 0=input
```

### Flash Operations
```bash
# Erase SPI flash
flash -e

# Probe SPI flash
flash -p

# Read SPI flash to file
flash -r output.bin -l 1024 -o 0
```

### Clock Configuration
```bash
# Set clock to 36MHz
flash -c 3

# Set clock to 72MHz
flash -c 4
```

## Device Status and Error Handling

The tool provides clear feedback about device connection status:

### Device Connected
```bash
$ flash -c 2
[INFO] iCELink device connected ✓
[INFO] Setting CLK source to 2...
```

### Device Not Connected
```bash
$ flash -c 2
[ERROR] iCELink device not connected or accessible. Please check USB connection.
```

### Pro-Only Features on Nano
```bash
$ flash -j 1
[ERROR] JTAG interface selection (-j) is not supported on iCESugar-nano boards.
[ERROR] This feature is only available on iCESugar-Pro boards.
[INFO] Available options for iCESugar-nano:
[INFO]   -c <1-4>  # Set CLK source (1=8MHz, 2=12MHz, 3=36MHz, 4=72MHz)
[INFO]   -e        # Erase flash
[INFO]   -p        # Probe flash
[INFO]   -r <FILE> # Read flash to file
[INFO]   -g <PIN>  # GPIO operations
```

## Board Compatibility

### iCESugar-nano (Supported)
- ✅ Clock configuration (`-c`)
- ✅ Flash operations (`-e`, `-p`, `-r`)
- ✅ GPIO operations (`-g`)
- ✅ Build and program operations

### iCESugar-Pro (Limited Support)
- ✅ All nano features
- ✅ JTAG interface selection (`-j`) - **Pro only**

## Uninstallation

### Option 1: One-Line Uninstallation (Recommended)
```bash
# With confirmation prompts
curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/uninstall.sh | bash

# Force removal without prompts
curl -s https://raw.githubusercontent.com/abhinav937/Lattice_NanoIce/main/uninstall.sh | bash -s -- --force
```

### Option 2: Manual Uninstallation
```bash
# Remove everything (with confirmation)
./uninstall.sh

# Remove everything without confirmation
./uninstall.sh --force

# Remove only flash tool and alias
./uninstall.sh --flash-only

# Remove only OSS CAD Suite
./uninstall.sh --oss-only

# Remove only package manager installed tools
./uninstall.sh --tools-only
```

### Option 3: Manual Removal (if script fails)
If the uninstall script fails due to permission issues, you can manually remove the components:

```bash
# Remove OSS CAD Suite
sudo rm -rf ~/opt/oss-cad-suite
sudo rmdir ~/opt  # if empty

# Remove flash tool
rm -f ~/.local/bin/flash_fpga.py
rmdir ~/.local/bin  # if empty

# Remove flash alias from bashrc/zshrc (edit manually)
# Remove these lines from ~/.bashrc or ~/.zshrc:
# # iCESugar-nano FPGA Flash Tool alias
# alias flash='python3 ~/.local/bin/flash_fpga.py'
```

## Requirements

- Linux (Ubuntu/Debian/Arch/Fedora/CentOS), macOS, or FreeBSD
- Python 3
- curl and tar
- sudo access for installation
- iCESugar-nano FPGA board

## Troubleshooting

### Common Issues

1. **Device not detected**
   ```bash
   [ERROR] iCELink device not connected or accessible. Please check USB connection.
   ```
   - Check USB cable connection
   - Ensure device is in programming mode
   - Verify USB permissions (Linux)

2. **Tools not found**
   ```bash
   [ERROR] Required tool 'yosys' is not installed or not in PATH
   ```
   - Run `./install.sh --update-only` to check installation
   - Manually source environment: `source ~/opt/oss-cad-suite/environment`

3. **Permission denied**
   ```bash
   [ERROR] No write permission to mount point
   ```
   - Run `./install.sh` to set up USB permissions
   - Check if device is mounted by another process

4. **Pro-only features on nano**
   ```bash
   [ERROR] JTAG interface selection (-j) is not supported on iCESugar-nano boards.
   ```
   - Use `-c` for clock configuration instead
   - Check available options in the error message

### General Troubleshooting Steps

1. **Check system requirements**: Ensure you have sufficient disk space (2GB+) and memory (2GB+)
2. **Verify installation**: Run `flash --help` to check if the tool is properly installed
3. **Check OSS CAD Suite**: Verify the installation at `~/opt/oss-cad-suite`
4. **Manual environment sourcing**: If tools aren't found, manually run `source ~/opt/oss-cad-suite/environment`
5. **Run with verbose output**: `flash top.v --verbose` for detailed error messages
6. **Check USB permissions**: Ensure your user has access to the USB device (Linux only)
7. **Update tools**: Run `./install.sh --update-only` to check for updates
8. **Uninstall issues**: If uninstall fails, use `--force` flag or manual removal commands

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.