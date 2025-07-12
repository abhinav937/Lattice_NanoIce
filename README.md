# iCESugar-nano FPGA Flash Tool

A comprehensive and efficient tool for synthesizing and programming iCESugar-nano FPGA boards. This tool provides a streamlined workflow from Verilog source files to programmed FPGA, with robust error handling and multiple programming methods.

## Installation

### Quick Installation (Recommended)

For Linux and macOS, use the automated installation script:

```bash
# Clone the repository
git clone https://github.com/yourusername/Lattice_NanoIce.git
cd Lattice_NanoIce

# Run the installation script
./install.sh
```

This script will:
- Install FPGA toolchain (yosys, nextpnr-ice40, icepack, icesprog)
- Set up USB permissions for the iCESugar-nano board
- Create a `flash` command alias

After installation, restart your terminal or run:
```bash
source ~/.bashrc  # or ~/.zshrc
```

### Uninstallation

```bash
# Remove everything (alias + tools)
./uninstall.sh

# Remove only the flash alias
./uninstall.sh --alias-only

# Remove only FPGA tools
./uninstall.sh --tools-only
```

### Manual Installation

Install the required FPGA toolchain:

```bash
# Ubuntu/Debian
sudo apt-get install yosys nextpnr-ice40 icepack

# macOS (using Homebrew)
brew install yosys nextpnr-ice40 icepack

# Arch Linux
sudo pacman -S yosys nextpnr-ice40 icepack
```

**Note**: `icesprog` is built from source from the [wuxx/icesugar repository](https://github.com/wuxx/icesugar/tree/master/tools).

## SSH Flash Tool

The `ssh_flash/` directory contains a tool for pushing files to a Raspberry Pi or remote device via SSH.

### Why SSH Push is Needed

When developing FPGA projects, you often have this setup:
- **Development machine**: Your main computer where you write Verilog code
- **Target device**: Raspberry Pi connected to the iCESugar-nano FPGA board

**The problem**: You need to transfer your Verilog files from your development machine to the Pi to program the FPGA.

**Traditional solutions** (cumbersome):
- Manually copy files via USB/SD card
- Use separate SSH/SCP commands each time
- Set up complex file sharing

**SSH Push solution**:
- Simple `ssh-push file.v` command
- Automatic file transfer to Pi
- Project-specific SSH configurations
- Works from any directory

**Typical workflow**:
1. Write Verilog code on your development machine
2. Run `ssh-push top.v` to send to Pi
3. SSH into Pi and run `flash top.v` to program FPGA
4. Repeat for each code change

### SSH Flash Installation

```bash
cd ssh_flash
./install.sh
```

### SSH Flash Usage

```bash
# Setup SSH configuration
ssh-push -s

# Push files to remote
ssh-push blinky.v
ssh-push file1.v file2.v

# Test connection
ssh-push -t

# List remote files
ssh-push -l
```

See `ssh_flash/README.md` for detailed documentation.

## Usage

### Basic Usage

```bash
# Simple single file programming
flash top.v

# With custom PCF file
flash top.v custom.pcf

# Multiple Verilog files
flash "file1.v,file2.v,file3.v" top.pcf

# Alternative: Direct Python execution
python3 flash_fpga.py top.v
```

### Available Flags

| Short Flag | Long Flag | Description |
|------------|-----------|-------------|
| `-v` | `--verbose` | Verbose output for debugging |
| `-n` | `--no-clean` | Keep intermediate files |
| `-c` | `--clock` | Set iCELink clock (1-4) |
| `-e` | `--erase` | Erase SPI flash |
| `-p` | `--probe` | Probe SPI flash |
| `-r` | `--read` | Read SPI flash to file |
| `-o` | `--offset` | SPI flash offset |
| `-l` | `--len` | Length of read/write |
| `-g` | `--gpio` | GPIO write/read file |
| `-m` | `--mode` | GPIO mode |
| `-j` | `--jtag-sel` | JTAG interface select |
| `-k` | `--clk-sel` | CLK source select |

### Advanced Options

```bash
# Verbose output for debugging
flash top.v -v                    # or flash top.v --verbose

# Set iCELink clock frequency
flash top.v -c 2                  # or flash top.v --clock 2 (12MHz)

# Keep intermediate files for inspection
flash top.v -n                    # or flash top.v --no-clean

# Combine options
flash top.v top.pcf -v -c 3 -n    # or flash top.v top.pcf --verbose --clock 3 --no-clean
```

### Clock Options

| Option | Frequency | Use Case |
|--------|-----------|----------|
| `1` | 8MHz | Low power, simple designs |
| `2` | 12MHz | Standard operation |
| `3` | 36MHz | High performance |
| `4` | 72MHz | Maximum performance |

## Workflow

1. **Input Validation** - Checks all files and tools
2. **Device Detection** - Verifies iCESugar-nano connection
3. **Clock Configuration** - Sets clock frequency if specified
4. **Synthesis** - Yosys converts Verilog to netlist
5. **Place & Route** - nextpnr-ice40 optimizes layout
6. **Bitstream Generation** - icepack creates programming file
7. **Programming** - icesprog or drag-and-drop method
8. **Cleanup** - Removes temporary files (unless --no-clean)

## Error Handling

The tool provides comprehensive error handling:

- **Missing tools** - Clear messages about required software
- **File validation** - Checks existence and extensions
- **Device detection** - Warns if iCESugar-nano not found
- **Programming failures** - Automatic fallback to alternative methods
- **Resource cleanup** - Ensures temporary files are removed

## Logging

The tool provides detailed logging:

- **Console output** - Real-time progress and errors
- **File logging** - Complete log with timestamps (saved in current directory)
- **Colored output** - Different colors for different log levels
- **Debug mode** - Verbose output with `-v` flag

Log files are saved as `icesugar_flash.log` in the directory where you run the command.

## Examples

### Simple LED Blink Project

```bash
# Create a simple LED blink design
echo 'module top(input clk, output reg led);
  reg [23:0] counter;
  always @(posedge clk) counter <= counter + 1;
  always @(posedge clk) led <= counter[23];
endmodule' > blink.v

# Create pin constraints
echo 'set_io clk 21
set_io led 35' > blink.pcf

# Program the FPGA
flash blink.v blink.pcf -c 2
```

### Complex Multi-file Project

```bash
# Program with multiple Verilog files
flash "uart.v,top.v,clocks.v" top.pcf -v -c 3
```

## Troubleshooting

### Common Issues

1. **"Command not found" errors**
   - Ensure FPGA toolchain is installed and in PATH
   - Check installation with `which yosys`

2. **"iCESugar-nano not found"**
   - Check USB connection
   - Verify device ID: `lsusb | grep 1d50:602b`

3. **"iCELink mount point not found"**
   - Device may not be in mass storage mode
   - Try pressing reset button on board

4. **Programming failures**
   - Tool automatically tries drag-and-drop method
   - Check USB permissions on Linux

### Debug Mode

Use `-v` flag for detailed debugging:

```bash
flash top.v -v
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.