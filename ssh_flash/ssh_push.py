#!/usr/bin/env python3
"""
SSH File Push Tool
A simple tool for pushing files to a remote device via SSH.
Built from first principles - no flashing, just file transfer.
"""

import os
import sys
import json
import argparse
import logging
import subprocess
import shutil
from pathlib import Path
from typing import List, Dict, Any, Optional
import getpass

VERSION = "1.1.0"
CONFIG_FILE = ".ssh_push_config.json"  # Local to current directory

def setup_logging(verbose: bool = False) -> None:
    """Setup logging configuration."""
    log_level = logging.DEBUG if verbose else logging.INFO
    
    # Clear any existing handlers
    logger = logging.getLogger()
    logger.handlers.clear()
    logger.setLevel(log_level)
    
    # Console handler
    console_handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

def load_config() -> Dict[str, Any]:
    """Load SSH configuration from file."""
    config_path = CONFIG_FILE  # Use relative path (current directory)
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            logging.warning(f"Failed to load config file: {e}")
    return {}

def save_config(config: Dict[str, Any]) -> None:
    """Save SSH configuration to file."""
    config_path = CONFIG_FILE  # Use relative path (current directory)
    try:
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        logging.info(f"Configuration saved to {config_path}")
    except IOError as e:
        logging.error(f"Failed to save config: {e}")

def setup_ssh_config() -> Dict[str, Any]:
    """Interactive setup of SSH configuration."""
    # Check if config already exists
    existing_config = load_config()
    
    if existing_config:
        print("SSH Configuration already exists!")
        print("Current configuration:")
        for key, value in existing_config.items():
            if key == 'password':
                print(f"  {key}: {'*' * len(str(value)) if value else 'None'}")
            else:
                print(f"  {key}: {value}")
        
        print("\nOptions:")
        print("1. Edit existing configuration")
        print("2. Create new configuration (overwrite)")
        print("3. Cancel")
        
        while True:
            choice = input("Choose option (1-3): ").strip()
            if choice == "1":
                return edit_ssh_config(existing_config)
            elif choice == "2":
                print("\nCreating new configuration...")
                break
            elif choice == "3":
                print("Setup cancelled.")
                return {}
            else:
                print("Please enter 1, 2, or 3.")
    
    print("SSH Configuration Setup")
    print("=" * 25)
    
    config = {}
    
    # Hostname (can include username@hostname)
    while True:
        hostname = input("Remote hostname/IP (e.g., pi@192.168.1.100): ").strip()
        if hostname:
            config['hostname'] = hostname
            break
        print("Hostname cannot be empty.")
    
    # Port
    port = input("SSH port (default: 22): ").strip()
    config['port'] = int(port) if port.isdigit() else 22
    
    # Remote working directory
    remote_dir = input("Remote working directory (default: ~/fpga_work): ").strip()
    config['remote_dir'] = remote_dir if remote_dir else "~/fpga_work"
    
    # Authentication method
    print("\nAuthentication method:")
    print("1. SSH key (recommended)")
    print("2. Password")
    
    while True:
        auth_choice = input("Choose authentication method (1 or 2): ").strip()
        if auth_choice == "1":
            config['auth_method'] = 'key'
            break
        elif auth_choice == "2":
            config['auth_method'] = 'password'
            break
        print("Please enter 1 or 2.")
    
    # SSH key path (if using key authentication)
    if config['auth_method'] == 'key':
        key_path = input("SSH key path (default: ~/.ssh/id_rsa): ").strip()
        config['key_path'] = key_path if key_path else "~/.ssh/id_rsa"
    
    # Test connection
    print("\nTesting SSH connection...")
    if test_ssh_connection(config):
        print("✓ SSH connection successful!")
        save_config(config)
        return config
    else:
        print("✗ SSH connection failed. Please check your configuration.")
        return {}

def edit_ssh_config(existing_config: Dict[str, Any]) -> Dict[str, Any]:
    """Edit existing SSH configuration."""
    print("Edit SSH Configuration")
    print("=" * 25)
    print("Current values shown in [brackets]. Press Enter to keep current value.")
    
    config = existing_config.copy()
    
    # Hostname
    current_hostname = existing_config.get('hostname', '')
    hostname = input(f"Remote hostname/IP [{current_hostname}]: ").strip()
    if hostname:
        config['hostname'] = hostname
    
    # Port
    current_port = existing_config.get('port', 22)
    port = input(f"SSH port [{current_port}]: ").strip()
    if port.isdigit():
        config['port'] = int(port)
    
    # Remote working directory
    current_remote_dir = existing_config.get('remote_dir', '~/fpga_work')
    remote_dir = input(f"Remote working directory [{current_remote_dir}]: ").strip()
    if remote_dir:
        config['remote_dir'] = remote_dir
    
    # Authentication method
    current_auth = existing_config.get('auth_method', 'key')
    print(f"\nCurrent authentication method: {current_auth}")
    print("1. SSH key (recommended)")
    print("2. Password")
    
    auth_choice = input("Choose authentication method (1 or 2) [Enter to keep current]: ").strip()
    if auth_choice == "1":
        config['auth_method'] = 'key'
    elif auth_choice == "2":
        config['auth_method'] = 'password'
    
    # SSH key path (if using key authentication)
    if config['auth_method'] == 'key':
        current_key_path = existing_config.get('key_path', '~/.ssh/id_rsa')
        key_path = input(f"SSH key path [{current_key_path}]: ").strip()
        if key_path:
            config['key_path'] = key_path
    
    # Test connection
    print("\nTesting SSH connection...")
    if test_ssh_connection(config):
        print("✓ SSH connection successful!")
        save_config(config)
        return config
    else:
        print("✗ SSH connection failed. Please check your configuration.")
        return {}

def test_ssh_connection(config: Dict[str, Any]) -> bool:
    """Test SSH connection to remote host."""
    try:
        hostname = config['hostname']
        port = config.get('port', 22)
        
        # Build SSH command
        ssh_cmd = ['ssh', '-p', str(port), hostname, 'echo "SSH connection test successful"']
        
        # Add key file if specified
        if config.get('auth_method') == 'key' and config.get('key_path'):
            key_path = os.path.expanduser(config['key_path'])
            if os.path.exists(key_path):
                ssh_cmd = ['ssh', '-i', key_path, '-p', str(port), hostname, 'echo "SSH connection test successful"']
        
        result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=10)
        return result.returncode == 0 and "SSH connection test successful" in result.stdout
    except Exception as e:
        logging.debug(f"SSH connection test failed: {e}")
        return False

def show_config() -> None:
    """Show current SSH configuration."""
    config = load_config()
    if config:
        print("Current SSH Configuration:")
        print("=" * 30)
        for key, value in config.items():
            if key == 'password':
                print(f"{key}: {'*' * len(str(value)) if value else 'None'}")
            else:
                print(f"{key}: {value}")
    else:
        print("No SSH configuration found.")
        print("Run with --setup to create configuration.")

def push_files(files: List[str], config: Dict[str, Any], verbose: bool = False) -> bool:
    """Push files to remote host using scp."""
    if not config:
        logging.error("No SSH configuration found. Run --setup first.")
        return False
    
    if not files:
        logging.error("No files specified to push.")
        return False
    
    hostname = config['hostname']
    port = config.get('port', 22)
    remote_dir = config['remote_dir']
    
    # Ensure remote directory exists
    if not ensure_remote_directory(config, remote_dir):
        logging.error(f"Failed to create remote directory: {remote_dir}")
        return False
    
    success_count = 0
    total_files = len(files)
    
    for file_path in files:
        if not os.path.exists(file_path):
            logging.warning(f"File not found: {file_path}")
            continue
        
        try:
            # Build scp command
            scp_cmd = ['scp', '-P', str(port)]
            
            # Add key file if specified
            if config.get('auth_method') == 'key' and config.get('key_path'):
                key_path = os.path.expanduser(config['key_path'])
                if os.path.exists(key_path):
                    scp_cmd.extend(['-i', key_path])
            
            # Add verbose flag if requested
            if verbose:
                scp_cmd.append('-v')
            
            # Add source and destination
            scp_cmd.extend([file_path, f"{hostname}:{remote_dir}/"])
            
            if verbose:
                logging.info(f"Executing: {' '.join(scp_cmd)}")
            
            result = subprocess.run(scp_cmd, capture_output=not verbose, text=True)
            
            if result.returncode == 0:
                logging.info(f"✓ Pushed: {file_path}")
                success_count += 1
            else:
                logging.error(f"✗ Failed to push {file_path}: {result.stderr}")
                
        except Exception as e:
            logging.error(f"✗ Error pushing {file_path}: {e}")
    
    logging.info(f"Push complete: {success_count}/{total_files} files transferred successfully")
    return success_count == total_files

def ensure_remote_directory(config: Dict[str, Any], remote_dir: str) -> bool:
    """Ensure remote directory exists."""
    try:
        hostname = config['hostname']
        port = config.get('port', 22)
        
        # Build SSH command to create directory
        ssh_cmd = ['ssh', '-p', str(port), hostname, f'mkdir -p {remote_dir}']
        
        # Add key file if specified
        if config.get('auth_method') == 'key' and config.get('key_path'):
            key_path = os.path.expanduser(config['key_path'])
            if os.path.exists(key_path):
                ssh_cmd = ['ssh', '-i', key_path, '-p', str(port), hostname, f'mkdir -p {remote_dir}']
        
        result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=10)
        return result.returncode == 0
    except Exception as e:
        logging.debug(f"Failed to create remote directory: {e}")
        return False

def list_remote_files(config: Dict[str, Any]) -> bool:
    """List files in remote working directory."""
    if not config:
        logging.error("No SSH configuration found. Run --setup first.")
        return False
    
    try:
        hostname = config['hostname']
        port = config.get('port', 22)
        remote_dir = config['remote_dir']
        
        # Build SSH command
        ssh_cmd = ['ssh', '-p', str(port), hostname, f'ls -la {remote_dir}']
        
        # Add key file if specified
        if config.get('auth_method') == 'key' and config.get('key_path'):
            key_path = os.path.expanduser(config['key_path'])
            if os.path.exists(key_path):
                ssh_cmd = ['ssh', '-i', key_path, '-p', str(port), hostname, f'ls -la {remote_dir}']
        
        result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            print(f"\nFiles in {remote_dir}:")
            print("=" * 40)
            print(result.stdout)
            return True
        else:
            logging.error(f"Failed to list remote files: {result.stderr}")
            return False
            
    except Exception as e:
        logging.error(f"Error listing remote files: {e}")
        return False

def main() -> int:
    """Main function."""
    parser = argparse.ArgumentParser(
        description="SSH File Push Tool - Push files to remote device",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ssh-push -s                         # Setup SSH configuration
  ssh-push -e                         # Edit existing configuration
  ssh-push blinky.v                   # Push single file
  ssh-push file1.v file2.v            # Push multiple files
  ssh-push -l                         # List remote files
  ssh-push -t                         # Test SSH connection
  ssh-push -c                         # Show configuration
  ssh-push -v blinky.v                # Push with verbose output
        """
    )
    
    parser.add_argument('files', nargs='*', metavar='FILE',
                       help='Files to push to remote host')
    parser.add_argument('--setup', '-s', action='store_true',
                       help='Setup SSH configuration')
    parser.add_argument('--edit', '-e', action='store_true',
                       help='Edit existing SSH configuration')
    parser.add_argument('--list', '-l', action='store_true',
                       help='List files in remote working directory')
    parser.add_argument('--test', '-t', action='store_true',
                       help='Test SSH connection')
    parser.add_argument('--config', '-c', action='store_true',
                       help='Show current configuration')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    parser.add_argument('--version', action='version', version=f'%(prog)s {VERSION}')
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(args.verbose)
    
    # Load configuration
    config = load_config()
    
    # Handle different commands
    if args.setup:
        if setup_ssh_config():
            return 0
        else:
            return 1
    
    elif args.edit:
        config = load_config()
        if not config:
            logging.error("No SSH configuration found. Run --setup first.")
            return 1
        if edit_ssh_config(config):
            return 0
        else:
            return 1
    
    elif args.config:
        show_config()
        return 0
    
    elif args.test:
        if not config:
            logging.error("No SSH configuration found. Run --setup first.")
            return 1
        
        if test_ssh_connection(config):
            print("✓ SSH connection successful!")
            return 0
        else:
            print("✗ SSH connection failed.")
            return 1
    
    elif args.list:
        if list_remote_files(config):
            return 0
        else:
            return 1
    
    elif args.files:
        if push_files(args.files, config, args.verbose):
            return 0
        else:
            return 1
    
    else:
        parser.print_help()
        return 0

if __name__ == "__main__":
    sys.exit(main()) 