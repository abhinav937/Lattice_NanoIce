# SSH Push Tool

A tool for pushing files to remote devices via SSH.

## Installation

```bash
chmod +x install.sh
./install.sh
```

The script will check for required dependencies:
- Python 3
- OpenSSH client (ssh, scp)

## Uninstallation

```bash
chmod +x uninstall.sh
./uninstall.sh
```

This will:
- Remove `ssh-push` from `/usr/local/bin/`
- Clean up any PATH entries in shell configuration files
- Remove SSH configuration file
- Create backups of modified configuration files

## Manual Cleanup

```bash
chmod +x cleanup.sh
./cleanup.sh
```

Useful when:
- Cloning the repository fresh
- Troubleshooting installation issues
- Ensuring a clean state before reinstalling

## Quick Start

1. **Setup SSH Configuration:**
   ```bash
   ssh-push -s
   ```
   This will prompt you for:
   - Remote hostname/IP (e.g., `pi@192.168.1.100`)
   - SSH port (default: 22)
   - Remote working directory (default: `~/fpga_work`)
   - Authentication method (SSH key or password)
   - SSH key path (if using key authentication)

2. **Test Connection:**
   ```bash
   ssh-push -t
   ```

3. **Push Files:**
   ```bash
   ssh-push file1.v file2.v icesugar_nano.pcf
   ```

4. **List Remote Files:**
   ```bash
   ssh-push -l
   ```

## Usage Examples

```bash
# Setup configuration
ssh-push -s                    # or ssh-push --setup

# Edit existing configuration
ssh-push -e                    # or ssh-push --edit

# Push single file
ssh-push blinky.v

# Push multiple files
ssh-push top.v clock.v icesugar_nano.pcf

# Push with verbose output
ssh-push top.v -v              # or ssh-push top.v --verbose

# List files on remote
ssh-push -l                    # or ssh-push --list

# Show current configuration
ssh-push -c                    # or ssh-push --config

# Test SSH connection
ssh-push -t                    # or ssh-push --test
```

## Configuration

The tool stores configuration in `.ssh_push_config.json` in the current directory:

```json
{
  "hostname": "pi@192.168.1.100",
  "port": 22,
  "remote_dir": "~/fpga_work",
  "auth_method": "key",
  "key_path": "~/.ssh/id_rsa"
}
```

**Benefits of local configuration:**
- Different SSH settings for different projects
- Configuration stays with the project
- Easy to share project-specific settings
- No conflicts between different projects

## SSH Key Setup

For secure authentication, set up SSH keys:

1. **Generate SSH key** (if you don't have one):
   ```bash
   ssh-keygen -t rsa -b 4096
   ```

2. **Copy public key to remote device:**
   ```bash
   ssh-copy-id pi@192.168.1.100
   ```

3. **Test key authentication:**
   ```bash
   ssh pi@192.168.1.100
   ```

## Troubleshooting

### SSH Connection Issues

1. **Check SSH service** on remote device:
   ```bash
   sudo systemctl status ssh
   ```

2. **Test basic SSH connection:**
   ```bash
   ssh pi@192.168.1.100
   ```

3. **Check firewall settings** on both local and remote devices

### Permission Issues

1. **Check SSH key permissions:**
   ```bash
   chmod 600 ~/.ssh/id_rsa
   chmod 644 ~/.ssh/id_rsa.pub
   ```

2. **Check remote directory permissions:**
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