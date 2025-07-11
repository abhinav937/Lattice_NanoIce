#!/usr/bin/env python3
"""
iCESugar-nano FPGA Flash Tool
A comprehensive tool for synthesizing and programming iCESugar-nano FPGA boards.
"""

import os
import sys
import subprocess
import shutil
import argparse
import logging
import time
import datetime
import shlex
import re
from pathlib import Path
from typing import List, Optional, Dict, Any
from contextlib import contextmanager

VERSION = "1.1.0"

# Constants
REQUIRED_TOOLS = ["yosys", "nextpnr-ice40", "icepack", "icesprog"]
ICE40_DEVICE_ID = "1d50:602b"
CLOCK_OPTIONS = {
    "1": "8MHz",
    "2": "12MHz", 
    "3": "36MHz",
    "4": "72MHz"
}

class ColoredFormatter(logging.Formatter):
    """Custom formatter with colored output for different log levels."""
    
    COLORS = {
        'DEBUG': '\033[36m',      # Cyan
        'INFO': '\033[32m',       # Green
        'WARNING': '\033[33m',    # Yellow
        'ERROR': '\033[31m',      # Red
        'CRITICAL': '\033[1;31m'  # Bright Red
    }

    def format(self, record: logging.LogRecord) -> str:
        """Format log record with color."""
        color = self.COLORS.get(record.levelname, '')
        reset = '\033[0m'
        
        # Get the base formatted message
        message = super().format(record)
        
        # Find and color only the log level part [LEVEL]
        import re
        level_pattern = r'\[(DEBUG|INFO|WARNING|ERROR|CRITICAL)\]'
        
        def color_level(match):
            level = match.group(1)
            level_color = self.COLORS.get(level, '')
            return f"{level_color}[{level}]{reset}"
        
        # Replace only the log level with color
        colored_message = re.sub(level_pattern, color_level, message)
        
        return colored_message

class FPGABuildError(Exception):
    """Custom exception for FPGA build errors."""
    pass

@contextmanager
def temporary_files(*files: str):
    """Context manager to clean up temporary files."""
    try:
        yield
    finally:
        for file_path in files:
            try:
                if os.path.exists(file_path):
                    os.remove(file_path)
                    logging.debug(f"Cleaned up temporary file: {file_path}")
            except OSError as e:
                logging.warning(f"Failed to remove {file_path}: {e}")

def setup_logging(verbose: bool = False) -> str:
    """Setup logging configuration with both console and file handlers.
    
    Args:
        verbose: Enable debug logging if True
        
    Returns:
        Path to the log file
    """
    log_level = logging.DEBUG if verbose else logging.INFO
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = f"icesugar_flash_{timestamp}.log"

    # Clear any existing handlers
    logger = logging.getLogger()
    logger.handlers.clear()
    logger.setLevel(log_level)

    # Console handler with improved formatting
    console_handler = logging.StreamHandler()
    if verbose:
        console_formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
    else:
        # Simplified format for non-verbose mode
        console_formatter = logging.Formatter('%(message)s')
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)

    # File handler (with color)
    file_handler = logging.FileHandler(log_file)
    file_formatter = ColoredFormatter('%(asctime)s [%(levelname)s] %(message)s')
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)

    if verbose:
        logging.info(f"Logging to {log_file}")
    return log_file

def check_command(cmd: str) -> bool:
    """Check if a command is available in PATH.
    
    Args:
        cmd: Command name to check
        
    Returns:
        True if command exists, False otherwise
    """
    if shutil.which(cmd) is None:
        logging.error(f"Required tool '{cmd}' is not installed or not in PATH.")
        return False
    return True

def check_file(filepath: str) -> bool:
    """Check if a file exists and is readable.
    
    Args:
        filepath: Path to the file to check
        
    Returns:
        True if file exists and is readable
    """
    if not os.path.isfile(filepath):
        logging.error(f"File '{filepath}' does not exist or is not accessible.")
        return False
    return True

def validate_extension(filepath: str, ext: str) -> bool:
    """Validate file extension.
    
    Args:
        filepath: Path to the file
        ext: Expected extension (with dot)
        
    Returns:
        True if extension matches
    """
    if not filepath.lower().endswith(ext.lower()):
        logging.error(f"File '{filepath}' must have '{ext}' extension.")
        return False
    return True

def run_cmd(cmd_list: List[str], error_msg: str, verbose: bool = False, 
           capture_output: bool = True) -> subprocess.CompletedProcess:
    """Execute a command with proper error handling.
    
    Args:
        cmd_list: List of command and arguments
        error_msg: Error message to display on failure
        verbose: Whether to show command output
        capture_output: Whether to capture command output
        
    Returns:
        CompletedProcess object
        
    Raises:
        FPGABuildError: If command execution fails
    """
    cmd_str = ' '.join(shlex.quote(c) for c in cmd_list)
    logging.debug(f"Executing: {cmd_str}")
    
    try:
        if verbose:
            # For verbose mode, stream output to console
            process = subprocess.run(
                cmd_list, 
                check=True, 
                capture_output=False,
                text=True
            )
        else:
            # For non-verbose mode, capture output for logging
            process = subprocess.run(
                cmd_list, 
                check=True, 
                capture_output=capture_output,
                text=True
            )
            if capture_output and process.stdout:
                logging.debug(f"Command output:\n{process.stdout}")
        
        return process
        
    except subprocess.CalledProcessError as e:
        error_output = e.stderr if e.stderr else "No error output available"
        logging.error(f"{error_msg}\nCommand: {cmd_str}\nError: {error_output}")
        raise FPGABuildError(f"{error_msg}: {e}")
    except FileNotFoundError as e:
        logging.error(f"Command not found: {cmd_list[0]}")
        raise FPGABuildError(f"Command '{cmd_list[0]}' not found: {e}")
    except Exception as e:
        logging.error(f"Unexpected error running command '{cmd_str}': {e}")
        raise FPGABuildError(f"Unexpected error: {e}")

def check_usb_device() -> Optional[str]:
    """Check for iCESugar-nano USB device and find serial port.
    
    Returns:
        Serial port path if found, None otherwise
    """
    try:
        # Check for device using lsusb
        lsusb_output = subprocess.check_output(["lsusb"], text=True)
        logging.debug(f"lsusb output:\n{lsusb_output}")

        if ICE40_DEVICE_ID not in lsusb_output:
            logging.error(f"iCESugar-nano ({ICE40_DEVICE_ID}) not found. Check USB connection.")
            return None

        # Look for serial devices
        tty_devices = []
        for pattern in ["/dev/ttyUSB*", "/dev/ttyACM*"]:
            try:
                result = subprocess.run(
                    ["ls", pattern],
                    capture_output=True,
                    text=True,
                    check=False,
                    stderr=subprocess.DEVNULL
                )
                if result.returncode == 0 and result.stdout.strip():
                    tty_devices.extend(result.stdout.strip().split())
            except Exception as e:
                logging.debug(f"Error checking {pattern}: {e}")

        if tty_devices:
            logging.info(f"Found serial devices: {', '.join(tty_devices)}")
            return tty_devices[0]
        else:
            logging.info("No serial devices found. Continuing without serial port.")
            return None
            
    except subprocess.CalledProcessError as e:
        logging.error(f"lsusb command failed: {e}")
        return None
    except Exception as e:
        logging.error(f"Unexpected error in USB device check: {e}")
        return None

def find_icelink_mount() -> str:
    """Find iCELink mount point for drag-and-drop programming.
    
    Returns:
        Mount point path
        
    Raises:
        FPGABuildError: If mount point not found
    """
    try:
        output = subprocess.check_output(["lsblk", "-f"], text=True)
        for line in output.splitlines():
            if re.search(r"iCELink", line, re.IGNORECASE):
                parts = line.split()
                if len(parts) >= 7 and parts[6]:
                    mount_point = parts[6]
                    logging.debug(f"iCELink mount point: {mount_point}")
                    return mount_point
                    
        logging.error("iCELink mount point not found. Device may not be in mass storage mode.")
        raise FPGABuildError("iCELink mount point not found")
        
    except subprocess.CalledProcessError as e:
        logging.error(f"lsblk command failed: {e}")
        raise FPGABuildError(f"Failed to find mount point: {e}")
    except Exception as e:
        logging.error(f"Error finding iCELink mount point: {e}")
        raise FPGABuildError(f"Mount point error: {e}")

def set_icelink_clock(clock_option: Optional[str]) -> None:
    """Set iCELink clock frequency.
    
    Args:
        clock_option: Clock option (1-4) or None to skip
    """
    if not clock_option:
        return
        
    if clock_option not in CLOCK_OPTIONS:
        logging.warning(f"Invalid clock option: {clock_option}")
        return
        
    try:
        frequency = CLOCK_OPTIONS[clock_option]
        logging.info(f"Setting iCELink clock to {frequency}...")
        run_cmd(["icesprog", "-c", clock_option], "Clock setting failed.", verbose=False)
        logging.info(f"Clock set to {frequency}")
    except FPGABuildError as e:
        logging.warning(f"Clock setting failed: {e}. Continuing anyway.")

def validate_input_files(verilog_files: List[str], pcf_file: str) -> None:
    """Validate all input files before processing.
    
    Args:
        verilog_files: List of Verilog file paths
        pcf_file: PCF file path
        
    Raises:
        FPGABuildError: If any file validation fails
    """
    # Validate Verilog files
    for v_file in verilog_files:
        if not check_file(v_file):
            raise FPGABuildError(f"Verilog file not found: {v_file}")
        if not validate_extension(v_file, ".v"):
            raise FPGABuildError(f"Invalid Verilog file extension: {v_file}")
    
    # Validate PCF file
    if not check_file(pcf_file):
        raise FPGABuildError(f"PCF file not found: {pcf_file}")
    if not validate_extension(pcf_file, ".pcf"):
        raise FPGABuildError(f"Invalid PCF file extension: {pcf_file}")

def check_required_tools() -> None:
    """Check that all required tools are available.
    
    Raises:
        FPGABuildError: If any required tool is missing
    """
    missing_tools = []
    for tool in REQUIRED_TOOLS:
        if not check_command(tool):
            missing_tools.append(tool)
    
    if missing_tools:
        raise FPGABuildError(f"Missing required tools: {', '.join(missing_tools)}")

def build_fpga(verilog_files: List[str], pcf_file: str, basename: str, 
              verbose: bool = False) -> Dict[str, str]:
    """Build FPGA bitstream from Verilog files.
    
    Args:
        verilog_files: List of Verilog file paths
        pcf_file: PCF file path
        basename: Base name for output files
        verbose: Enable verbose output
        
    Returns:
        Dictionary with generated file paths
    """
    output_files = {
        'json': f"{basename}.json",
        'asc': f"{basename}.asc", 
        'bit': f"{basename}.bit"
    }
    
    print("╔══════════════════════════════════════════════════════════════════════════════╗")
    print("║                              FPGA BUILD PROCESS                              ║")
    print("╚══════════════════════════════════════════════════════════════════════════════╝")
    
    # Synthesis with Yosys
    print("🔧 Step 1/3: Synthesis with Yosys")
    logging.info("Synthesizing with Yosys...")
    verilog_args = ' '.join(shlex.quote(v) for v in verilog_files)
    yosys_script = f"read_verilog {verilog_args}; synth_ice40 -json {shlex.quote(output_files['json'])}"
    run_cmd(["yosys", "-p", yosys_script], "Yosys synthesis failed.", verbose)

    # Place and route with nextpnr-ice40
    print("🔧 Step 2/3: Place and Route with nextpnr-ice40")
    logging.info("Running place and route with nextpnr-ice40...")
    run_cmd([
        "nextpnr-ice40", "--lp1k", "--package", "cm36",
        "--json", output_files['json'], 
        "--pcf", pcf_file, 
        "--asc", output_files['asc']
    ], "nextpnr-ice40 failed.", verbose)

    # Generate bitstream with icepack
    print("🔧 Step 3/3: Generate Bitstream with icepack")
    logging.info("Generating bitstream with icepack...")
    run_cmd(["icepack", output_files['asc'], output_files['bit']], 
            "icepack failed.", verbose)
    
    print("✅ FPGA build completed successfully!")
    return output_files

def program_fpga(bit_file: str, verbose: bool = False) -> bool:
    """Program FPGA using available methods.
    
    Args:
        bit_file: Path to bitstream file
        verbose: Enable verbose output
        
    Returns:
        True if programming succeeded, False otherwise
    """
    print("╔══════════════════════════════════════════════════════════════════════════════╗")
    print("║                            FPGA PROGRAMMING                                 ║")
    print("╚══════════════════════════════════════════════════════════════════════════════╝")
    
    # Try icesprog first
    print("🚀 Method 1/2: Programming with icesprog")
    logging.info("Programming FPGA with icesprog...")
    try:
        run_cmd(["icesprog", "-w", bit_file], "icesprog programming failed.", verbose)
        logging.info("Programming completed successfully using icesprog.")
        print("✅ Programming completed successfully using icesprog!")
        return True
    except FPGABuildError:
        logging.warning("icesprog failed. Trying drag-and-drop method...")
        print("⚠️  icesprog failed, trying alternative method...")
        
        # Try drag-and-drop method
        print("🚀 Method 2/2: Drag-and-drop programming")
        try:
            mount_point = find_icelink_mount()
            print(f"📁 Copying bitstream to: {mount_point}")
            shutil.copy2(bit_file, mount_point)
            
            # Sync filesystem
            try:
                subprocess.run(["sync"], check=True, capture_output=True)
                print("💾 Filesystem synchronized")
            except (subprocess.CalledProcessError, FileNotFoundError):
                logging.debug("sync command not available, skipping")
            
            # Wait for device to process
            print("⏳ Waiting for device to process bitstream...")
            time.sleep(3)
            logging.info("Bitstream copied to iCELink mass storage device.")
            print("✅ Bitstream copied to iCELink mass storage device!")
            return True
            
        except Exception as e:
            logging.error(f"Drag-and-drop method failed: {e}")
            print(f"❌ Drag-and-drop method failed: {e}")
            return False

def main() -> int:
    """Main function with improved error handling and efficiency."""
    
    # Create a more detailed help description
    description = f"""
╔══════════════════════════════════════════════════════════════════════════════╗
║                    iCESugar-nano FPGA Flash Tool v{VERSION}                    ║
║                                                                              ║
║  A comprehensive tool for synthesizing and programming iCESugar-nano FPGA   ║
║  boards. Supports multiple Verilog files, automatic PCF detection, and     ║
║  dual programming methods (icesprog + drag-and-drop fallback).              ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""
    
    epilog = """
╔══════════════════════════════════════════════════════════════════════════════╗
║                              EXAMPLES                                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Basic Usage:                                                                ║
║    flash top.v                              # Single file, auto PCF          ║
║    flash top.v top.pcf                      # Single file, custom PCF        ║
║    flash "file1.v,file2.v,file3.v" top.pcf # Multiple Verilog files        ║
║                                                                              ║
║  Advanced Usage:                                                             ║
║    flash top.v --verbose --clock 2          # Verbose + 12MHz clock          ║
║    flash top.v --no-clean                   # Keep intermediate files        ║
║    flash top.v --clock 4                    # Maximum performance (72MHz)    ║
║                                                                              ║
║  Clock Options:                                                              ║
║    1 = 8MHz (low power)    2 = 12MHz (standard)                             ║
║    3 = 36MHz (high perf)   4 = 72MHz (maximum)                              ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

For more information, visit: https://github.com/wuxx/icesugar
"""
    
    parser = argparse.ArgumentParser(
        description=description,
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    # Add arguments with better descriptions
    parser.add_argument("verilog_file", 
                       help="Verilog file(s) to synthesize (comma-separated for multiple files)")
    parser.add_argument("pcf_file", nargs="?", 
                       help="Pin constraint file (auto-detected if not specified)")
    
    # Optional arguments
    parser.add_argument("-v", "--verbose", action="store_true", 
                       help="Enable verbose output with detailed command execution")
    parser.add_argument("--no-clean", action="store_true", 
                       help="Keep intermediate files (.json, .asc, .bit) for inspection")
    parser.add_argument("--clock", choices=list(CLOCK_OPTIONS.keys()), 
                       help="Set iCELink clock frequency (1=8MHz, 2=12MHz, 3=36MHz, 4=72MHz)")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    
    args = parser.parse_args()

    try:
        # Setup logging
        log_file = setup_logging(args.verbose)
        
        print("╔══════════════════════════════════════════════════════════════════════════════╗")
        print("║                        iCESugar-nano FPGA Flash Tool                        ║")
        print("╚══════════════════════════════════════════════════════════════════════════════╝")
        
        # Parse and validate input files
        verilog_files = [v.strip() for v in args.verilog_file.split(",")]
        pcf_file = args.pcf_file or f"{Path(verilog_files[0]).stem}.pcf"
        
        print(f"📁 Verilog files: {', '.join(verilog_files)}")
        print(f"📁 Using PCF file: {pcf_file}")
        logging.info(f"Verilog files: {', '.join(verilog_files)}")
        logging.info(f"Using PCF file: {pcf_file}")
        
        # Validate inputs
        print("🔍 Validating input files...")
        validate_input_files(verilog_files, pcf_file)
        print("✅ Input files validated")
        
        # Check required tools
        print("🔍 Checking required tools...")
        check_required_tools()
        print("✅ All required tools found")
        
        # Check USB device
        print("🔍 Checking for iCESugar-nano device...")
        serial_port = check_usb_device()
        if not serial_port:
            print("⚠️  iCESugar-nano not detected. Programming may fail.")
            logging.warning("iCESugar-nano not detected. Programming may fail.")
        else:
            print("✅ iCESugar-nano device detected")
        
        # Set clock if specified
        if args.clock:
            print(f"⚡ Setting iCELink clock to {CLOCK_OPTIONS[args.clock]}...")
            set_icelink_clock(args.clock)
        
        # Build FPGA
        basename = Path(verilog_files[0]).stem
        output_files = build_fpga(verilog_files, pcf_file, basename, args.verbose)
        
        # Program FPGA
        if not program_fpga(output_files['bit'], args.verbose):
            logging.error("All programming methods failed.")
            print("❌ All programming methods failed.")
            return 1
        
        # Cleanup
        if not args.no_clean:
            print("🧹 Cleaning up intermediate files...")
            with temporary_files(output_files['json'], output_files['asc'], output_files['bit']):
                pass
            print("✅ Cleanup completed")
        else:
            print("📁 Keeping intermediate files (--no-clean)")
            logging.info("Keeping intermediate files (--no-clean).")
        
        print("╔══════════════════════════════════════════════════════════════════════════════╗")
        print("║                              SUCCESS! 🎉                                   ║")
        print("║                        FPGA programming completed!                         ║")
        print("╚══════════════════════════════════════════════════════════════════════════════╝")
        logging.info("FPGA programming completed successfully!")
        return 0
        
    except FPGABuildError as e:
        logging.error(f"Build error: {e}")
        return 1
    except KeyboardInterrupt:
        logging.info("Operation cancelled by user.")
        return 1
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
