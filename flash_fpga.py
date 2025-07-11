#!/usr/bin/env python3

import os
import sys
import subprocess
import shutil
import argparse
import logging
import time
import datetime
import shlex

VERSION = "1.0.1"

class ColoredFormatter(logging.Formatter):
    COLORS = {
        'DEBUG': '\033[36m',  # Cyan
        'INFO': '\033[32m',   # Green
        'WARNING': '\033[33m',  # Yellow
        'ERROR': '\033[31m',   # Red
        'CRITICAL': '\033[1;31m'  # Bright Red
    }

    def format(self, record):
        color = self.COLORS.get(record.levelname, '')
        message = super().format(record)
        return f"{color}{message}\033[0m"

def setup_logging(verbose=False):
    log_level = logging.DEBUG if verbose else logging.INFO
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = f"icesugar_flash_{timestamp}.log"

    logger = logging.getLogger()
    logger.setLevel(log_level)

    # Console without color
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
    logger.addHandler(console_handler)

    # File with color
    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(ColoredFormatter('%(asctime)s [%(levelname)s] %(message)s'))
    logger.addHandler(file_handler)

    logging.info(f"Logging to {log_file}")

def check_command(cmd):
    if shutil.which(cmd) is None:
        logging.error(f"{cmd} is not installed.")
        sys.exit(1)

def check_file(filepath):
    if not os.path.isfile(filepath):
        logging.error(f"File {filepath} does not exist.")
        sys.exit(1)
    return True

def validate_extension(filepath, ext):
    if not filepath.lower().endswith(ext):
        logging.error(f"File {filepath} must have {ext} extension.")
        sys.exit(1)

def run_cmd(cmd_list, error_msg, verbose=False):
    logging.debug(f"Executing: {' '.join(shlex.quote(c) for c in cmd_list)}")
    try:
        if verbose:
            process = subprocess.run(cmd_list, check=True, capture_output=True, text=True)
            logging.debug(f"Command output:\n{process.stdout}")
            print(process.stdout, file=sys.stdout)
        else:
            process = subprocess.run(cmd_list, check=True, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"{error_msg}\n{e.stderr}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Unexpected error running command: {e}")
        sys.exit(1)

def check_usb_device():
    try:
        lsusb_output = subprocess.check_output(["lsusb"]).decode()
        logging.debug(f"lsusb output:\n{lsusb_output}")

        if "1d50:602b" not in lsusb_output:
            logging.error("iCESugar-nano (1d50:602b) not found. Check connection.")
            sys.exit(1)

        # Look for tty device (optional)
        try:
            result = subprocess.run(
                ["ls", "/dev/ttyUSB*", "/dev/ttyACM*"],
                capture_output=True,
                text=True,
                check=False,
                stderr=subprocess.DEVNULL
            )
            if result.returncode == 0:
                tty_output = result.stdout.split()
                logging.info(f"Found serial devices: {', '.join(tty_output)}")
                return tty_output[0] if tty_output else None
            else:
                logging.info("No ttyUSB/ACM devices found. Continuing without serial port.")
                return None
        except Exception as e:
            logging.warning(f"Error checking tty devices: {e}. Continuing without serial port.")
            return None
    except subprocess.CalledProcessError as e:
        logging.error(f"lsusb command failed: {e}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Unexpected error in USB device check: {e}")
        sys.exit(1)

        
def find_icelink_mount():
    try:
        output = subprocess.check_output(["lsblk", "-f"]).decode()
        for line in output.splitlines():
            if re.search(r"iCELink", line, re.IGNORECASE):
                parts = line.split()
                if len(parts) >= 7 and parts[6]:
                    logging.debug(f"iCELink mount point: {parts[6]}")
                    return parts[6]
        logging.error("iCELink mount point not found.")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Error finding iCELink mount point: {e}")
        sys.exit(1)

def set_icelink_clock(clock_option):
    if not clock_option:
        return
    clock_map = {"1": "8MHz", "2": "12MHz", "3": "36MHz", "4": "72MHz"}
    try:
        logging.info(f"Setting iCELink clock to {clock_map[clock_option]}...")
        run_cmd(["icesprog", "-c", str(clock_option)], "Clock setting failed.", verbose=False)
    except Exception as e:
        logging.warning(f"Clock set failed: {e}. Continuing anyway.")

def main():
    parser = argparse.ArgumentParser(
        description="iCESugar-nano FPGA Flash Tool",
        epilog="Example: %(prog)s top.v top.pcf --verbose --clock 2"
    )
    parser.add_argument("verilog_file", help="Verilog file(s), comma-separated if multiple")
    parser.add_argument("pcf_file", nargs="?", help="Pin constraint file")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--no-clean", action="store_true", help="Keep intermediate files")
    parser.add_argument("--clock", choices=["1", "2", "3", "4"], help="Set iCELink clock (1=8MHz, 2=12MHz, 3=36MHz, 4=72MHz)")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    args = parser.parse_args()

    setup_logging(args.verbose)

    verilog_files = [v.strip() for v in args.verilog_file.split(",")]
    for v in verilog_files:
        check_file(v)
        validate_extension(v, ".v")
    logging.info(f"Verilog files: {', '.join(verilog_files)}")

    pcf_file = args.pcf_file or os.path.splitext(verilog_files[0])[0] + ".pcf"
    check_file(pcf_file)
    validate_extension(pcf_file, ".pcf")
    logging.info(f"Using PCF file: {pcf_file}")

    for tool in ["yosys", "nextpnr-ice40", "icepack", "icesprog"]:
        check_command(tool)

    serial_port = check_usb_device()

    set_icelink_clock(args.clock)

    basename = os.path.splitext(os.path.basename(verilog_files[0]))[0]
    json_file = f"{basename}.json"
    asc_file = f"{basename}.asc"
    bit_file = f"{basename}.bit"

    logging.info("Synthesizing with Yosys...")
    yosys_cmd = ["yosys", "-p", f"read_verilog {' '.join(shlex.quote(v) for v in verilog_files)}; synth_ice40 -json {shlex.quote(json_file)}"]
    run_cmd(yosys_cmd, "Yosys synthesis failed.", args.verbose)

    logging.info("Running place and route with nextpnr-ice40...")
    run_cmd([
        "nextpnr-ice40", "--lp1k", "--package", "cm36",
        "--json", json_file, "--pcf", pcf_file, "--asc", asc_file
    ], "nextpnr failed.", args.verbose)

    logging.info("Generating bitstream with icepack...")
    run_cmd(["icepack", asc_file, bit_file], "icepack failed.", args.verbose)

    logging.info("Programming FPGA with icesprog...")
    try:
        run_cmd(["icesprog", "-w", bit_file], "icesprog -w failed.", args.verbose)
        logging.info("Programming completed successfully using icesprog -w.")
    except SystemExit:
        logging.warning("icesprog -w failed. Trying drag-and-drop...")
        mount_point = find_icelink_mount()
        try:
            shutil.copy(bit_file, mount_point)
            subprocess.run(["sync"], check=True)
            time.sleep(5)
            logging.info("Bitstream copied to iCELink mass storage.")
        except Exception as e:
            logging.error(f"Drag-and-drop method failed: {e}")
            sys.exit(1)

    if not args.no_clean:
        for f in [json_file, asc_file, bit_file]:
            if os.path.exists(f):
                os.remove(f)
                logging.debug(f"Deleted {f}")
    else:
        logging.info("Keeping intermediate files (--no-clean).")

    logging.info("All done!")

if __name__ == "__main__":
    main()
