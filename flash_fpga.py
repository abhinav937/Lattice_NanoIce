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
import signal
import threading
from pathlib import Path
from typing import List, Optional, Dict, Any, Tuple
from contextlib import contextmanager
import tempfile

VERSION = "1.5.0"

# Constants
REQUIRED_TOOLS = ["yosys", "nextpnr-ice40", "icepack", "icesprog"]
OSS_CAD_SUITE_ENV = os.path.expanduser("~/opt/oss-cad-suite/environment")
ICE40_DEVICE_ID = "1d50:602b"
CLOCK_OPTIONS = {
    "1": "8MHz",
    "2": "12MHz", 
    "3": "36MHz",
    "4": "72MHz"
}

MAX_LOG_LINES = 100
LOG_FILE = "icesugar_flash.log"
MAX_RETRIES = 3
RETRY_DELAY = 2
BUILD_TIMEOUT = 300  # 5 minutes for build operations
PROGRAM_TIMEOUT = 60  # 1 minute for programming operations

# Global flag for graceful shutdown
shutdown_requested = False

def signal_handler(signum, frame):
    """Handle interrupt signals gracefully."""
    global shutdown_requested
    shutdown_requested = True
    logging.info("Shutdown requested, cleaning up...")

# Register signal handlers
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

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

@contextmanager
def temporary_directory():
    """Context manager for temporary directory creation and cleanup."""
    temp_dir = tempfile.mkdtemp(prefix="icesugar_")
    try:
        yield temp_dir
    finally:
        try:
            shutil.rmtree(temp_dir)
            logging.debug(f"Cleaned up temporary directory: {temp_dir}")
        except OSError as e:
            logging.warning(f"Failed to remove temporary directory {temp_dir}: {e}")

def retry_operation(operation, max_retries=MAX_RETRIES, delay=RETRY_DELAY, operation_name="operation"):
    """Retry an operation with exponential backoff."""
    for attempt in range(max_retries):
        try:
            if shutdown_requested:
                raise FPGABuildError("Operation cancelled by user")
            
            result = operation()
            if attempt > 0:
                logging.info(f"{operation_name} succeeded on attempt {attempt + 1}")
            return result
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            logging.warning(f"{operation_name} failed on attempt {attempt + 1}: {e}")
            if attempt < max_retries - 1:
                time.sleep(delay * (2 ** attempt))  # Exponential backoff
                logging.info(f"Retrying {operation_name} in {delay * (2 ** attempt)} seconds...")
    
    raise FPGABuildError(f"{operation_name} failed after {max_retries} attempts")

def setup_logging(verbose: bool = False) -> str:
    """Setup logging configuration with both console and file handlers.
    
    Args:
        verbose: Enable debug logging if True
        
    Returns:
        Path to the log file
    """
    log_level = logging.DEBUG if verbose else logging.INFO
    # Use a single log file
    log_file = LOG_FILE

    # Clear any existing handlers
    logger = logging.getLogger()
    logger.handlers.clear()
    logger.setLevel(log_level)

    # Console handler (with color)
    console_handler = logging.StreamHandler()
    console_formatter = ColoredFormatter('%(asctime)s [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)

    # File handler (with color)
    file_handler = logging.FileHandler(log_file, mode='a')
    file_formatter = ColoredFormatter('%(asctime)s [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)

    # Remove or comment out the following line in setup_logging:
    # logging.info(f"Logging to {log_file}")
    return log_file

# FIFO log rotation: keep only the last MAX_LOG_LINES in the log file
def rotate_log_file(log_file: str):
    try:
        with open(log_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        if len(lines) > MAX_LOG_LINES:
            with open(log_file, 'w', encoding='utf-8') as f:
                f.writelines(lines[-MAX_LOG_LINES:])
    except Exception:
        pass

# Patch logging to rotate after each log record
def patch_logging_for_rotation(log_file: str):
    old_emit = logging.FileHandler.emit
    def new_emit(self, record):
        old_emit(self, record)
        if self.baseFilename == os.path.abspath(log_file):
            rotate_log_file(log_file)
    logging.FileHandler.emit = new_emit

def source_oss_cad_suite() -> Dict[str, str]:
    """Source the OSS CAD Suite environment and return the modified environment.
    
    Returns:
        Dictionary with modified environment variables
    """
    env = os.environ.copy()
    
    if os.path.exists(OSS_CAD_SUITE_ENV):
        try:
            # Execute the environment script and capture the environment
            result = subprocess.run(
                ["bash", "-c", f"source {OSS_CAD_SUITE_ENV} && env"],
                capture_output=True,
                text=True,
                check=True
            )
            
            # Parse the environment variables
            for line in result.stdout.splitlines():
                if '=' in line:
                    key, value = line.split('=', 1)
                    env[key] = value
            
            logging.debug("OSS CAD Suite environment sourced")
        except subprocess.CalledProcessError as e:
            logging.warning(f"Failed to source OSS CAD Suite environment: {e}")
        except Exception as e:
            logging.warning(f"Failed to source OSS CAD Suite environment: {e}")
    else:
        logging.debug("OSS CAD Suite environment file not found, using system PATH")
    
    return env

def check_command(cmd: str) -> bool:
    """Check if a command is available in PATH (including OSS CAD Suite).
    
    Args:
        cmd: Command name to check
        
    Returns:
        True if command exists, False otherwise
    """
    # First check in current PATH
    if shutil.which(cmd) is not None:
        return True
    
    # If not found, check with OSS CAD Suite environment
    env = source_oss_cad_suite()
    if shutil.which(cmd, path=env.get('PATH', '')) is not None:
        return True
    
    logging.error(f"Required tool '{cmd}' is not installed or not in PATH (including OSS CAD Suite).")
    return False

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
           capture_output: bool = True, timeout: Optional[int] = None) -> subprocess.CompletedProcess:
    """Execute a command with proper error handling and timeout.
    
    Args:
        cmd_list: List of command and arguments
        error_msg: Error message to display on failure
        verbose: Whether to show command output
        capture_output: Whether to capture command output
        timeout: Timeout in seconds (None for no timeout)
        
    Returns:
        CompletedProcess object
        
    Raises:
        FPGABuildError: If command execution fails
    """
    cmd_str = ' '.join(shlex.quote(c) for c in cmd_list)
    logging.debug(f"Executing: {cmd_str}")
    
    # Source OSS CAD Suite environment for FPGA tools
    env = source_oss_cad_suite()
    
    try:
        if shutdown_requested:
            raise FPGABuildError("Operation cancelled by user")
        
        if verbose:
            # For verbose mode, stream output to console with progress
            process = subprocess.run(
                cmd_list, 
                check=True, 
                capture_output=False,
                text=True,
                timeout=timeout,
                env=env
            )
        else:
            # For non-verbose mode, capture output for logging
            process = subprocess.run(
                cmd_list, 
                check=True, 
                capture_output=capture_output,
                text=True,
                timeout=timeout,
                env=env
            )
            if capture_output and process.stdout:
                logging.debug(f"Command output:\n{process.stdout}")
        
        return process
        
    except subprocess.TimeoutExpired as e:
        logging.error(f"{error_msg} - Command timed out after {timeout} seconds")
        raise FPGABuildError(f"{error_msg} - Timeout after {timeout}s: {e}")
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

def run_cmd_with_progress(cmd_list: List[str], error_msg: str, timeout: Optional[int] = None) -> subprocess.CompletedProcess:
    """Execute a command with real-time progress output."""
    cmd_str = ' '.join(shlex.quote(c) for c in cmd_list)
    logging.info(f"Executing: {cmd_str}")
    
    # Source OSS CAD Suite environment for FPGA tools
    env = source_oss_cad_suite()
    
    try:
        process = subprocess.Popen(
            cmd_list,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True,
            env=env
        )
        
        # Read output in real-time
        output_lines = []
        while True:
            if shutdown_requested:
                process.terminate()
                raise FPGABuildError("Operation cancelled by user")
            
            if process.stdout is None:
                break
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            
            if line:
                line = line.rstrip()
                output_lines.append(line)
                # Show progress for long-running operations
                if any(keyword in line.lower() for keyword in ['progress', 'percent', '%', 'building', 'synthesizing']):
                    print(f"  {line}")
        
        return_code = process.wait()
        if return_code != 0:
            error_output = '\n'.join(output_lines[-10:])  # Last 10 lines
            logging.error(f"{error_msg}\nCommand: {cmd_str}\nError output:\n{error_output}")
            raise FPGABuildError(f"{error_msg} (return code: {return_code})")
        
        return subprocess.CompletedProcess(cmd_list, return_code, '\n'.join(output_lines), None)
        
    except subprocess.TimeoutExpired as e:
        process.terminate()
        logging.error(f"{error_msg} - Command timed out after {timeout} seconds")
        raise FPGABuildError(f"{error_msg} - Timeout after {timeout}s")
    except Exception as e:
        if 'process' in locals():
            process.terminate()
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

def check_icelink_status() -> bool:
    """Check if iCELink device is connected and accessible.
    
    Returns:
        True if device is connected and accessible, False otherwise
    """
    try:
        # Try a simple icesprog command to test connection
        result = subprocess.run(
            ["icesprog", "-p"],  # Probe command to test connection
            capture_output=True,
            text=True,
            timeout=5
        )
        
        # Check if device is connected
        if "iCELink open fail" in result.stderr or "iCELink open fail" in result.stdout:
            return False
        elif result.returncode == 0:
            return True
        else:
            return False
            
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return False
    except Exception:
        return False

def check_existing_icelink_mount() -> Optional[str]:
    """Check for existing iCELink mount point without attempting to mount.
    
    Returns:
        Mount point path if found, None otherwise
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
        # If lsblk didnt find it, try to find common mount locations
        import glob
        common_mount_patterns = [
            "/media/icelink",
            "/media/iCELink",
            "/mnt/icelink",
            "/mnt/iCELink",
            "/run/media/*/icelink",
            "/run/media/*/iCELink"
        ]
        for mount_pattern in common_mount_patterns:
            matches = glob.glob(mount_pattern)
            for match in matches:
                if os.path.ismount(match):
                    logging.debug(f"iCELink mount point found via glob: {match}")
                    return match
        return None
    except subprocess.CalledProcessError as e:
        logging.debug(f"lsblk command failed: {e}")
        return None
    except Exception as e:
        logging.debug(f"Error checking existing mount: {e}")
        return None

def find_and_mount_icelink_device() -> str:
    """Find and mount iCELink device if not already mounted."""
    
    # First check for existing mount
    existing_mount = check_existing_icelink_mount()
    if existing_mount:
        logging.info(f"iCELink device already mounted at: {existing_mount}")
        return existing_mount
    
    logging.info("No existing iCELink mount found, attempting to mount device...")
    # Find the iCELink device
    device_path = None
    try:
        # Check for iCELink device using lsblk
        output = subprocess.check_output(["lsblk", "-f"], text=True)
        for line in output.splitlines():
            if re.search(r"iCELink", line, re.IGNORECASE):
                parts = line.split()
                if len(parts) >= 1:
                    device_path = parts[0]
                    logging.debug(f"Found iCELink device: {device_path}")
                    break
        
        # If not found via lsblk, try common device patterns
        if not device_path:
            import glob
            device_patterns = ["/dev/sda", "/dev/sdb", "/dev/sdc", "/dev/sdd"]
            for pattern in device_patterns:
                if os.path.exists(pattern):
                    # Check if it's the iCELink device by looking at filesystem
                    try:
                        result = subprocess.run(
                            ["blkid", pattern], 
                            capture_output=True, 
                            text=True, 
                            check=False
                        )
                        if result.returncode == 0 and "iCELink" in result.stdout:
                            device_path = pattern
                            logging.debug(f"Found iCELink device via blkid: {device_path}")
                            break
                    except (subprocess.CalledProcessError, FileNotFoundError):
                        continue
        
        if not device_path:
            raise FPGABuildError("iCELink device not found. Check USB connection and ensure device is in mass storage mode.")
        
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to detect iCELink device: {e}")
        raise FPGABuildError(f"Device detection failed: {e}")
    
    # Check if device is already mounted
    try:
        mount_output = subprocess.check_output(["mount"], text=True)
        if device_path in mount_output:
            logging.info(f"Device {device_path} is already mounted")
            # Extract mount point from mount output
            for line in mount_output.splitlines():
                if device_path in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        mount_point = parts[2]
                        logging.info(f"Using existing mount point: {mount_point}")
                        return mount_point
    except subprocess.CalledProcessError as e:
        logging.warning(f"Could not check mount status: {e}")
    
    # Create mount point if it doesnt exist
    mount_point = "/mnt/icelink"
    try:
        os.makedirs(mount_point, exist_ok=True)
        logging.debug(f"Ensured mount point exists: {mount_point}")
    except OSError as e:
        logging.error(f"Failed to create mount point {mount_point}: {e}")
        raise FPGABuildError(f"Mount point creation failed: {e}")
    
    # Check filesystem type and permissions
    try:
        # Check if we have permission to mount
        if os.geteuid() != 0:
            logging.warning("Not running as root. Mount operation may fail.")
        
        # Check filesystem type
        blkid_result = subprocess.run(
            ["blkid", device_path],
            capture_output=True,
            text=True
        )
        
        if blkid_result.returncode == 0:
            if "vfat" in blkid_result.stdout.lower() or "fat" in blkid_result.stdout.lower():
                filesystem_type = "vfat"
                mount_options = ["-o", "rw,umask=000"]
            else:
                filesystem_type = "auto"
                mount_options = []
            
            logging.info(f"Detected filesystem type: {filesystem_type}")
        else:
            filesystem_type = "auto"
            mount_options = []
            logging.warning("Could not determine filesystem type, using auto")
        
        # Mount the device
        mount_cmd = ["mount", "-t", filesystem_type] + mount_options + [device_path, mount_point]
        logging.info(f"Mounting {device_path} to {mount_point}...")
        
        result = subprocess.run(
            mount_cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=30
        )
        
        if result.returncode != 0:
            error_msg = result.stderr if result.stderr else "Unknown mount error"
            logging.error(f"Mount failed: {error_msg}")
            # Try without filesystem type specification
            if filesystem_type != "auto":
                logging.info("Retrying mount with auto filesystem detection...")
                mount_cmd = ["mount"] + mount_options + [device_path, mount_point]
                result = subprocess.run(
                    mount_cmd,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=30
                )
                if result.returncode != 0:
                    error_msg = result.stderr if result.stderr else "Unknown mount error"
                    raise FPGABuildError(f"Mount failed even with auto detection: {error_msg}")
        
        # Verify mount was successful
        if not os.path.ismount(mount_point):
            raise FPGABuildError(f"Mount verification failed: {mount_point} is not a mount point")
        
        logging.info(f"Successfully mounted {device_path} to {mount_point}")
        return mount_point
        
    except subprocess.TimeoutExpired:
        logging.error("Mount operation timed out")
        raise FPGABuildError("Mount operation timed out")
    except subprocess.CalledProcessError as e:
        logging.error(f"Mount command failed: {e}")
        raise FPGABuildError(f"Mount command failed: {e}")
    except Exception as e:
        logging.error(f"Unexpected error during mount: {e}")
        raise FPGABuildError(f"Mount error: {e}")

def find_icelink_mount() -> str:
    """Find iCELink mount point for drag-and-drop programming.
    
    Returns:
        Mount point path
        
    Raises:
        FPGABuildError: If mount point not found
    """
    # First check for existing mount
    existing_mount = check_existing_icelink_mount()
    if existing_mount:
        return existing_mount
    
    # If no existing mount found, try to mount the device
    logging.info("No existing iCELink mount found, attempting to mount device...")
    return find_and_mount_icelink_device()

def set_icelink_clock(clock_option: Optional[int]) -> None:
    """Set iCELink clock frequency.
    
    Args:
        clock_option: Clock option (1-4) or None to skip
    """
    if not clock_option:
        return
        
    clock_str = str(clock_option)
    if clock_str not in CLOCK_OPTIONS:
        logging.warning(f"Invalid clock option: {clock_option}")
        return
        
    try:
        frequency = CLOCK_OPTIONS[clock_str]
        logging.info(f"Setting iCELink clock to {frequency}...")
        run_cmd(["icesprog", "-c", clock_str], "Clock setting failed.", verbose=False)
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

def check_system_resources() -> None:
    """Check if system has sufficient resources for FPGA build."""
    try:
        # Check available memory
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()
            match = re.search(r'MemAvailable:\s+(\d+)', meminfo)
            if match:
                available_mb = int(match.group(1)) // 1024
                if available_mb < 1024:  # Less than 1GB
                    logging.warning(f"Low memory detected: {available_mb}MB available. Build may fail.")
        
        # Check disk space
        statvfs = os.statvfs('.')
        free_gb = (statvfs.f_frsize * statvfs.f_bavail) / (1024**3)
        if free_gb < 1:  # Less than 1GB
            logging.warning(f"Low disk space detected: {free_gb:.1f}GB available. Build may fail.")
            
    except Exception as e:
        logging.debug(f"Could not check system resources: {e}")

def cleanup_on_exit():
    """Cleanup function called on exit."""
    global shutdown_requested
    if shutdown_requested:
        logging.info("Cleaning up after shutdown request...")
        # Additional cleanup can be added here

def build_fpga(verilog_files: List[str], pcf_file: str, basename: str, 
              verbose: bool = False) -> Dict[str, str]:
    """Build FPGA bitstream from Verilog files with retry logic and progress tracking.
    
    Args:
        verilog_files: List of Verilog file paths
        pcf_file: PCF file path
        basename: Base name for output files
        verbose: Enable verbose output
        
    Returns:
        Dictionary with generated file paths
    """
    # Create output directory
    out_dir = "out"
    os.makedirs(out_dir, exist_ok=True)
    
    output_files = {
        'json': os.path.join(out_dir, f"{basename}.json"),
        'asc': os.path.join(out_dir, f"{basename}.asc"), 
        'bin': os.path.join(out_dir, f"{basename}.bin")
    }
    
    def synthesis_step():
        """Synthesis with Yosys."""
        logging.info("Synthesizing with Yosys...")
        verilog_args = ' '.join(shlex.quote(v) for v in verilog_files)
        yosys_script = f"read_verilog {verilog_args}; synth_ice40 -json {shlex.quote(output_files['json'])}"
        
        if verbose:
            run_cmd_with_progress(["yosys", "-p", yosys_script], "Yosys synthesis failed.", BUILD_TIMEOUT)
        else:
            run_cmd(["yosys", "-p", yosys_script], "Yosys synthesis failed.", verbose, timeout=BUILD_TIMEOUT)
    
    def place_route_step():
        """Place and route with nextpnr-ice40."""
        logging.info("Running place and route with nextpnr-ice40...")
        cmd = [
            "nextpnr-ice40", "--lp1k", "--package", "cm36",
            "--json", output_files['json'], 
            "--pcf", pcf_file, 
            "--asc", output_files['asc']
        ]
        
        if verbose:
            run_cmd_with_progress(cmd, "nextpnr-ice40 failed.", BUILD_TIMEOUT)
        else:
            run_cmd(cmd, "nextpnr-ice40 failed.", verbose, timeout=BUILD_TIMEOUT)
    
    def bitstream_step():
        """Generate bitstream with icepack."""
        logging.info("Generating bitstream with icepack...")
        run_cmd(["icepack", output_files['asc'], output_files['bin']], 
                "icepack failed.", verbose, timeout=BUILD_TIMEOUT)
    
    # Execute build steps with retry logic
    try:
        retry_operation(synthesis_step, operation_name="Yosys synthesis")
        retry_operation(place_route_step, operation_name="Place and route")
        retry_operation(bitstream_step, operation_name="Bitstream generation")
        
        # Verify output files exist
        for file_type, file_path in output_files.items():
            if not os.path.exists(file_path):
                raise FPGABuildError(f"Expected output file not found: {file_path}")
        
        logging.info(f"FPGA build completed successfully. Output files in: {out_dir}")
        return output_files
        
    except Exception as e:
        # Clean up partial output files
        for file_path in output_files.values():
            try:
                if os.path.exists(file_path):
                    os.remove(file_path)
            except OSError:
                pass
        raise e

def program_fpga(bit_file: str, verbose: bool = False, force_dragdrop: bool = False) -> bool:
    """Program FPGA using available methods with retry logic.
    
    Args:
        bit_file: Path to bitstream file
        verbose: Enable verbose output
        force_dragdrop: If True, skip icesprog and use drag-and-drop only
        
    Returns:
        True if programming succeeded, False otherwise
    """
    def program_with_icesprog():
        """Program using icesprog."""
        logging.info("Programming FPGA with icesprog...")
        run_cmd(["icesprog", "-w", bit_file], "icesprog programming failed.", verbose, timeout=PROGRAM_TIMEOUT)
        logging.info("Programming completed successfully using icesprog.")
        return True
    
    def program_with_dragdrop():
        """Program using drag-and-drop method with robust mount/copy checks."""
        logging.info("Trying drag-and-drop programming method...")
        try:
            mount_point = find_icelink_mount()
            logging.info(f"Using iCELink mount point: {mount_point}")
        except Exception as e:
            logging.error(f"Failed to find or mount iCELink device: {e}")
            raise FPGABuildError(f"Failed to find or mount iCELink device: {e}")

        # Check write permissions
        if not os.access(mount_point, os.W_OK):
            logging.error(f"No write permission to mount point: {mount_point}")
            raise FPGABuildError(f"No write permission to mount point: {mount_point}")

        # Copy bitstream file
        try:
            dest_path = os.path.join(mount_point, os.path.basename(bit_file))
            logging.info(f"Copying bitstream to {dest_path}...")
            shutil.copy2(bit_file, dest_path)
        except Exception as e:
            logging.error(f"Failed to copy bitstream to mount point: {e}")
            raise FPGABuildError(f"Failed to copy bitstream to mount point: {e}")

        # Sync filesystem
        try:
            subprocess.run(["sync"], check=True, capture_output=True, timeout=10)
        except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
            logging.debug("sync command not available or timed out, skipping")

        # Wait for device to process (increased to 5s)
        logging.info("Waiting 5 seconds for device to process the bitstream...")
        time.sleep(5)

        # Verify file exists on device
        if not os.path.exists(dest_path):
            logging.error(f"Bitstream file not found on device after copy: {dest_path}")
            raise FPGABuildError(f"Bitstream file not found on device after copy: {dest_path}")
        else:
            logging.info(f"Bitstream successfully copied to {dest_path}")

        logging.info("Bitstream copied to iCELink mass storage device.")
        return True
    
    if force_dragdrop:
        try:
            retry_operation(program_with_dragdrop, operation_name="drag-and-drop programming")
            return True
        except Exception as e:
            logging.error(f"Drag-and-drop programming failed: {e}")
            return False
    # Try icesprog first with retry
    try:
        retry_operation(program_with_icesprog, operation_name="icesprog programming")
        return True
    except FPGABuildError as e:
        logging.warning(f"icesprog failed: {e}")
        # Try drag-and-drop method as fallback
        try:
            retry_operation(program_with_dragdrop, operation_name="drag-and-drop programming")
            return True
        except Exception as e:
            logging.error(f"All programming methods failed: {e}")
            return False

def main() -> int:
    """Main function with improved error handling, reliability, and efficiency."""
    # Store original environment
    original_env = os.environ.copy()
    
    # Ensure OSS CAD Suite environment is sourced at startup
    try:
        if os.path.exists(OSS_CAD_SUITE_ENV):
            # Source the environment and update current process environment
            env_dict = source_oss_cad_suite()
            for key, value in env_dict.items():
                os.environ[key] = value
            logging.debug("OSS CAD Suite environment sourced at startup")
    except Exception as e:
        logging.warning(f"Failed to source OSS CAD Suite environment at startup: {e}")
    
    def custom_error_handler(message):
        if "unrecognized arguments" in message:
            # Extract the unrecognized argument from the message
            import re
            match = re.search(r"unrecognized arguments: ([^\s]+)", message)
            arg = match.group(1) if match else "unknown"
            if arg == "-k":
                print("ERROR: Option '-k' is not recognized.", file=sys.stderr)
                print("Did you mean '-c' for CLK source selection?", file=sys.stderr)
                print("Usage: flash -c <1-4>  # Set CLK source (1=8MHz, 2=12MHz, 3=36MHz, 4=72MHz)", file=sys.stderr)
            else:
                print(f"ERROR: Option '{arg}' is not recognized.", file=sys.stderr)
                print("Use 'flash --help' to see all available options.", file=sys.stderr)
        elif "expected one argument" in message:
            if "-c" in message:
                print("ERROR: Option '-c' requires a value.", file=sys.stderr)
                print("Usage: flash -c <1-4>  # Set CLK source (1=8MHz, 2=12MHz, 3=36MHz, 4=72MHz)", file=sys.stderr)
            elif "-g" in message:
                print("ERROR: Option '-g' requires a GPIO pin.", file=sys.stderr)
                print("Usage: flash -g <PIN>  # GPIO pin (e.g., PA5, PB3)", file=sys.stderr)
            elif "-r" in message:
                print("ERROR: Option '-r' requires a filename.", file=sys.stderr)
                print("Usage: flash -r <FILE>  # Read flash to file", file=sys.stderr)
            else:
                print("ERROR: Missing required argument.", file=sys.stderr)
                print("Use 'flash --help' to see all available options.", file=sys.stderr)
        else:
            print(f"ERROR: {message}", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(
        prog="flash",
        description="iCESugar-nano FPGA Flash Tool",
        epilog="""Examples:
  flash top.v top.pcf          # Build and program
  flash top.v top.pcf -v -c 2  # Verbose with 12MHz clock
  flash -g PA5 --gpio-read     # Read GPIO pin
  flash -e                     # Erase flash
  flash -p                     # Probe flash
  flash -c 3                   # Set clock to 36MHz""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        add_help=False  # We'll handle help manually
    )
    parser.error = custom_error_handler
    
    # Positional arguments
    parser.add_argument("verilog_file", nargs="?", help="Verilog file(s) for build/program")
    parser.add_argument("pcf_file", nargs="?", help="Pin constraint file (auto-detected)")
    
    # Build options
    build_group = parser.add_argument_group("Build Options")
    build_group.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    build_group.add_argument("-n", "--no-clean", action="store_true", help="Keep intermediate files")
    build_group.add_argument("-b", "--build-only", action="store_true", help="Build only, skip programming")
    build_group.add_argument("-D", "--force-dragdrop", action="store_true", help="Force drag-and-drop programming")
    
    # Clock and interface options
    config_group = parser.add_argument_group("Configuration")
    config_group.add_argument("-c", "--clk-sel", type=int, choices=[1,2,3,4], 
                             help="CLK source select: 1=8MHz, 2=12MHz, 3=36MHz, 4=72MHz")
    config_group.add_argument("-j", "--jtag-sel", type=int, choices=[1,2], 
                             help="JTAG interface (1 or 2) - iCESugar-Pro only")
    
    # Flash operations
    flash_group = parser.add_argument_group("Flash Operations")
    flash_group.add_argument("-e", "--erase", action="store_true", help="Erase SPI flash")
    flash_group.add_argument("-p", "--probe", action="store_true", help="Probe SPI flash")
    flash_group.add_argument("-r", "--read", metavar="FILE", help="Read flash to file")
    flash_group.add_argument("-o", "--offset", type=int, metavar="BYTES", help="Flash offset")
    flash_group.add_argument("-l", "--len", type=int, metavar="BYTES", help="Read/write length")
    
    # GPIO operations
    gpio_group = parser.add_argument_group("GPIO Operations")
    gpio_group.add_argument("-g", "--gpio", metavar="PIN", help="GPIO pin (e.g., PA5, PB3)")
    gpio_group.add_argument("-m", "--mode", type=int, choices=[0,1], help="GPIO mode (0=input, 1=output)")
    gpio_group.add_argument("--gpio-read", action="store_true", help="Read GPIO value")
    gpio_group.add_argument("--gpio-write", action="store_true", help="Write GPIO value")
    gpio_group.add_argument("--gpio-value", type=int, help="GPIO value to write")
    
    # Version
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    
    # Handle help manually
    if len(sys.argv) > 1 and sys.argv[1] in ["-h", "--help"]:
        parser.print_help()
        return 0
    
    try:
        args = parser.parse_args()
    except SystemExit:
        # The custom error handler should have already printed the error
        return 1

    try:
        # Setup logging
        log_file = setup_logging(args.verbose)
        patch_logging_for_rotation(log_file)
        
        # Check system resources before starting
        check_system_resources()
        
        # Register cleanup function
        import atexit
        atexit.register(cleanup_on_exit)

        # Handle erase, probe, and other icesprog features before build/program
        if args.erase:
            # Check device status first
            if not check_icelink_status():
                logging.error("iCELink device not connected or accessible. Please check USB connection.")
                return 1
            logging.info("Erasing SPI flash...")
            run_cmd(["icesprog", "-e"], "Failed to erase SPI flash.", verbose=False, capture_output=True)
            return 0
        if args.probe:
            # Check device status first
            if not check_icelink_status():
                logging.error("iCELink device not connected or accessible. Please check USB connection.")
                return 1
            logging.info("Probing SPI flash...")
            run_cmd(["icesprog", "-p"], "Failed to probe SPI flash.", verbose=True, capture_output=False)
            return 0
        if args.read:
            # Check device status first
            if not check_icelink_status():
                logging.error("iCELink device not connected or accessible. Please check USB connection.")
                return 1
            cmd = ["icesprog", "-r", args.read]
            if args.offset is not None:
                cmd += ["-o", str(args.offset)]
            if args.len is not None:
                cmd += ["-l", str(args.len)]
            logging.info(f"Reading SPI flash to {args.read}...")
            run_cmd(cmd, "Failed to read SPI flash.", verbose=True, capture_output=False)
            return 0
        if args.gpio:
            # Check device status first
            if not check_icelink_status():
                logging.error("iCELink device not connected or accessible. Please check USB connection.")
                return 1
            
            # Validate GPIO pin format
            if not re.match(r'^P[A-F][0-9]+$', args.gpio):
                logging.error(f"Invalid GPIO pin format: {args.gpio}. Use format P<PORT><PIN> (e.g., PA5, PB3)")
                return 1
            
            # Extract port and pin from GPIO string
            port = args.gpio[1]  # A, B, C, D, E, F
            pin = int(args.gpio[2:])  # Pin number
            
            # Validate pin range (0-15)
            if pin < 0 or pin > 15:
                logging.error(f"Invalid GPIO pin number: {pin}. Must be 0-15")
                return 1
            
            # Convert port letter to number (A=10, B=11, C=12, D=13, E=14, F=15)
            port_num = ord(port) - ord('A') + 10
            
            if args.mode is not None:
                # Set GPIO mode
                mode_str = "in" if args.mode == 0 else "out"
                logging.info(f"Setting GPIO {args.gpio} mode to {mode_str}...")
                cmd = ["icesprog", "-g", args.gpio, "-m", mode_str]
                run_cmd(cmd, f"Failed to set GPIO {args.gpio} mode.", verbose=True, capture_output=False)
                return 0
            elif args.gpio_read:
                # Read GPIO value
                logging.info(f"Reading GPIO {args.gpio} value...")
                cmd = ["icesprog", "-r", "-g", args.gpio]
                run_cmd(cmd, f"Failed to read GPIO {args.gpio}.", verbose=True, capture_output=False)
                return 0
            elif args.gpio_write:
                # Write GPIO value
                if args.gpio_value is None:
                    logging.error("GPIO value must be specified for write operations (--gpio-value)")
                    return 1
                logging.info(f"Writing value {args.gpio_value} to GPIO {args.gpio}...")
                cmd = ["icesprog", "-w", "-g", args.gpio, str(args.gpio_value)]
                run_cmd(cmd, f"Failed to write to GPIO {args.gpio}.", verbose=True, capture_output=False)
                return 0
            else:
                logging.error("GPIO operation not specified. Use --gpio-read, --gpio-write, or -m for mode setting")
                return 1
        if args.jtag_sel:
            # JTAG selection is only supported on iCESugar-Pro, not iCESugar-nano
            print("ERROR: JTAG interface selection (-j) is not supported on iCESugar-nano boards.", file=sys.stderr)
            print("ERROR: This feature is only available on iCESugar-Pro boards.", file=sys.stderr)
            return 1
        if args.clk_sel:
            # Check device status first
            if not check_icelink_status():
                logging.error("iCELink device not connected or accessible. Please check USB connection.")
                return 1
            logging.info(f"Setting CLK source to {args.clk_sel}...")
            run_cmd(["icesprog", "-c", str(args.clk_sel)], "Failed to set CLK source.", verbose=False, capture_output=True)
            return 0
        # If only icesprog operations were requested, skip build/program
        if args.erase or args.probe or args.read or args.gpio or args.jtag_sel or args.clk_sel:
            return 0

        # If we reach here, build/program is requested, so Verilog file is required
        if not args.verilog_file:
            print("ERROR: Verilog file(s) must be specified for build/program operations.", file=sys.stderr)
            print("Usage: flash <verilog_file> [pcf_file] [options]", file=sys.stderr)
            print("Examples:", file=sys.stderr)
            print("  Build and program: flash top.v top.pcf -v -c 2", file=sys.stderr)
            print("  GPIO operations: flash -g PA5 --gpio-read", file=sys.stderr)
            print("  Flash operations: flash -e (erase), flash -p (probe)", file=sys.stderr)
            logging.error("Verilog file(s) must be specified for build/program operations.")
            return 1
        # Parse and validate input files
        verilog_files = [v.strip() for v in args.verilog_file.split(",")] if args.verilog_file else []
        pcf_file = args.pcf_file or f"{Path(verilog_files[0]).stem}.pcf" if verilog_files else None
        logging.info(f"Verilog files: {', '.join(verilog_files)}")
        logging.info(f"Using PCF file: {pcf_file}")
        if not pcf_file:
            print("ERROR: PCF file must be specified or auto-detectable for build/program operations.", file=sys.stderr)
            print("Usage: flash <verilog_file> [pcf_file] [options]", file=sys.stderr)
            print("Examples:", file=sys.stderr)
            print("  Build and program: flash top.v top.pcf -v -c 2", file=sys.stderr)
            print("  GPIO operations: flash -g PA5 --gpio-read", file=sys.stderr)
            print("  Flash operations: flash -e (erase), flash -p (probe)", file=sys.stderr)
            logging.error("PCF file must be specified or auto-detectable for build/program operations.")
            return 1
        # Validate inputs
        validate_input_files(verilog_files, pcf_file)
        
        # Check required tools
        check_required_tools()
        
        # Check USB device
        serial_port = check_usb_device()
        # Only warn if no serial devices are found at all
        if serial_port is None:
            logging.warning("iCESugar-nano not detected. Programming may fail.")
        

        
        # Build FPGA with progress tracking
        logging.info("Starting FPGA build process...")
        basename = Path(verilog_files[0]).stem
        output_files = build_fpga(verilog_files, pcf_file, basename, args.verbose)
        
        if args.build_only:
            logging.info(f"Build completed. Bitstream saved as: {output_files['bin']}")
            return 0        
        # Program FPGA with retry logic
        logging.info("Starting FPGA programming process...")
        if not program_fpga(output_files['bin'], args.verbose, args.force_dragdrop):
            logging.error("All programming methods failed.")
            return 1
        
        # Cleanup with better error handling
        if not args.no_clean:
            try:
                with temporary_files(output_files['json'], output_files['asc'], output_files['bin']):
                    pass
                logging.info("Cleaned up intermediate files.")
            except Exception as e:
                logging.warning(f"Cleanup failed: {e}")
        else:
            logging.info("Keeping intermediate files (--no-clean).")
        
        logging.info("FPGA programming completed successfully!")
        
        # Restore original environment
        os.environ.clear()
        os.environ.update(original_env)
        logging.debug("OSS CAD Suite environment removed")
        
        return 0
        
    except FPGABuildError as e:
        logging.error(f"Build error: {e}")
        
        # Restore original environment on error
        os.environ.clear()
        os.environ.update(original_env)
        logging.debug("OSS CAD Suite environment removed (error cleanup)")
        
        return 1
    except KeyboardInterrupt:
        logging.info("Operation cancelled by user.")
        
        # Restore original environment on interrupt
        os.environ.clear()
        os.environ.update(original_env)
        logging.debug("OSS CAD Suite environment removed (interrupt cleanup)")
        
        return 1
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        
        # Restore original environment on unexpected error
        os.environ.clear()
        os.environ.update(original_env)
        logging.debug("OSS CAD Suite environment removed (error cleanup)")
        
        return 1

if __name__ == "__main__":
    sys.exit(main())
