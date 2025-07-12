# SSH Push Tool

A simple, first-principles SSH file pushing tool for transferring files to remote devices (like Raspberry Pi) via SSH.

## Features

- **Simple SSH Configuration**: Easy setup with interactive configuration
- **File Transfer**: Push files to remote working directory using SCP
- **SSH Key Support**: Secure authentication using SSH keys
- **Linux Only**: Designed specifically for Linux environments
- **No Dependencies**: Uses only standard Python libraries and system SSH tools

## Installation

1. Run the installation script:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

2. The script will check for required dependencies:
   - Python 3
   - OpenSSH client (ssh, scp)

## Uninstallation

To remove ssh-push from your system:

```bash
chmod +x uninstall.sh
./uninstall.sh
```

This will:
- Remove `ssh-push` from `/usr/local/bin/`
- Clean up any PATH entries in shell configuration files
- Remove SSH configuration file
- Create backups of modified configuration files

## Quick Start

1. **Setup SSH Configuration**:
   ```bash
   ./ssh_push.py --setup
   ```
   This will prompt you for:
   - Remote hostname/IP (e.g., `pi@192.168.1.100`)
   - SSH port (default: 22)
   - Remote working directory (default: `~/fpga_work`)
   - Authentication method (SSH key or password)
   - SSH key path (if using key authentication)

2. **Test Connection**:
   ```bash
   ./ssh_push.py --test
   ```

3. **Push Files**:
   ```bash
   ./ssh_push.py --push file1.v file2.v icesugar_nano.pcf
   ```

4. **List Remote Files**:
   ```bash
   ./ssh_push.py --list
   ```

## Usage Examples

```bash
# Setup configuration
./ssh_push.py --setup

# Push Verilog files to remote
./ssh_push.py --push top.v clock.v icesugar_nano.pcf

# Push with verbose output
./ssh_push.py --push top.v --verbose

# List files on remote
./ssh_push.py --list

# Show current configuration
./ssh_push.py --config

# Test SSH connection
./ssh_push.py --test
```

## Shortcut Usage: ssh-push

A shortcut script named `ssh-push` is provided for convenience. This allows you to run the tool with a simple command instead of calling the Python script directly.

### Setup (Linux)

Make the shortcut executable:
```bash
chmod +x ssh-push
```

### Usage

You can now use the shortcut as follows:
```bash
./ssh-push --setup
./ssh-push --push file1.v file2.v
./ssh-push --list
./ssh-push --test
```

This is equivalent to running `python3 ssh_push.py ...` but is more convenient.

## Configuration

The tool stores configuration in `~/.ssh_push_config.json`:

```json
{
  "hostname": "pi@192.168.1.100",
  "port": 22,
  "remote_dir": "~/fpga_work",
  "auth_method": "key",
  "key_path": "~/.ssh/id_rsa"
}
```

## SSH Key Setup (Recommended)

For secure authentication, set up SSH keys:

1. **Generate SSH key** (if you don't have one):
   ```bash
   ssh-keygen -t rsa -b 4096
   ```

2. **Copy public key to remote device**:
   ```bash
   ssh-copy-id pi@192.168.1.100
   ```

3. **Test key authentication**:
   ```bash
   ssh pi@192.168.1.100
   ```

## Design Principles

This tool is built from first principles with these goals:

- **Simplicity**: No complex dependencies or installation procedures
- **Linux Focus**: Designed specifically for Linux environments
- **File Transfer Only**: Focuses solely on pushing files to remote working directory
- **Standard Tools**: Uses only SSH/SCP and Python standard library
- **No Flashing**: Does not include FPGA flashing features - just file transfer

## Troubleshooting

### SSH Connection Issues

1. **Check SSH service** on remote device:
   ```bash
   sudo systemctl status ssh
   ```

2. **Test basic SSH connection**:
   ```bash
   ssh pi@192.168.1.100
   ```

3. **Check firewall settings** on both local and remote devices

### Permission Issues

1. **Check SSH key permissions**:
   ```bash
   chmod 600 ~/.ssh/id_rsa
   chmod 644 ~/.ssh/id_rsa.pub
   ```

2. **Check remote directory permissions**:
   ```bash
   ssh pi@192.168.1.100 "ls -la ~/fpga_work"
   ```

### File Transfer Issues

1. **Check disk space** on remote device:
   ```bash
   ssh pi@192.168.1.100 "df -h"
   ```

2. **Check file permissions** on source files:
   ```bash
   ls -la file1.v file2.v
   ```

## License

This tool is part of the Lattice NanoIce project. 