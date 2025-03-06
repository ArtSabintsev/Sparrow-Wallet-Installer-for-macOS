# Sparrow Wallet Installer for macOS

A secure, convenient script for downloading, verifying, and installing Sparrow Bitcoin Wallet on macOS. 


## Note
The script and README were created with Claude Sonnet 3.7 on March 5, 2025.

## Features

- **Secure by Default**: Verifies PGP signatures and SHA-256 checksums
- **Automatic Installation**: Handles DMG mounting and proper application installation
- **Upgrade-Friendly**: Safely replaces existing installations
- **Simple to Use**: Single command to fully verify and install

## Why Use This Script?

Sparrow Wallet is a powerful Bitcoin wallet that prioritizes security and privacy. This script enhances your security by:

1. **Automating cryptographic verification** - Ensures the software hasn't been tampered with
2. **Simplifying the installation process** - No need to manually mount DMGs and drag to Applications
3. **Providing clean upgrades** - Properly handles existing installations

## Requirements

- macOS
- curl (pre-installed on macOS)
- gpg (can be installed via Homebrew with `brew install gnupg`)

## Installation

### Quick Start

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/sparrow-installer.git
   cd sparrow-installer
   ```

2. Make the script executable:
   ```
   chmod +x sparrow_install.sh
   ```

3. Run the script:
   ```
   ./sparrow_install.sh
   ```

4. If you encounter permission issues, you may need to use sudo:
   ```
   sudo ./sparrow_install.sh
   ```

### Command Line Options

- `--debug`: Enable detailed debugging information
- `--skip-verify`: Skip signature verification (not recommended for security reasons)

## How It Works

1. **Download**: Fetches the latest Sparrow Wallet DMG file
2. **Verification**: Downloads and validates PGP signatures and checksums
3. **Installation**: Mounts the DMG, checks for existing installations, and installs to /Applications
4. **Cleanup**: Unmounts the DMG and removes temporary files

## Configuration

By default, the script installs version 2.1.3 for Apple Silicon (aarch64). To install a different version or architecture, edit the following variables in the script:

```bash
# Use the specific version
VERSION="2.1.3"

# Set filenames
DMG_FILE="Sparrow-$VERSION-aarch64.dmg"
```

For Intel Macs, change `aarch64` to `x86_64`.

## Security Considerations

- The script verifies both the manifest signature and the DMG file checksum
- PGP keys are fetched from keybase.io for Craig Raw (Sparrow Wallet developer)
- The verification can be bypassed with `--skip-verify` but this is not recommended

## Troubleshooting

### Common Issues

1. **GPG Not Installed**
   
   Solution: Install GPG using Homebrew
   ```
   brew install gnupg
   ```

2. **Permission Denied When Installing**
   
   Solution: Run with sudo
   ```
   sudo ./sparrow_install.sh
   ```

3. **Sparrow Is Running**
   
   The script will detect if Sparrow is running and prompt you to close it before continuing.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This script is provided as-is without any warranties. Always ensure you trust the source of any script before running it on your system, especially those that require elevated privileges.

---

*This project is not officially affiliated with Sparrow Wallet.*