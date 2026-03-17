# Sparrow Wallet Installer for macOS

A secure, convenient script for downloading, verifying, and installing Sparrow Bitcoin Wallet on macOS. 

## Note
The script and README were created by Claude Sonnet 3.7 on March 5, 2025.

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
   git clone https://github.com/ArtSabintsev/Sparrow-Wallet-Installer-for-macOS.git
   cd Sparrow-Wallet-Installer-for-macOS
   ```

2. Make the script executable:
   ```
   chmod +x sparrow_verify.sh
   ```

3. Run the script:
   ```
   ./sparrow_verify.sh
   ```

4. If you encounter permission issues, you may need to use sudo:
   ```
   sudo ./sparrow_verify.sh
   ```

### Command Line Options

- `--debug`: Enable detailed debugging information
- `--skip-verify`: Skip signature verification (not recommended for security reasons)

## How It Works

1. **Download**: Fetches the latest Sparrow Wallet DMG file
2. **PGP Verification**: Downloads and validates PGP signatures against Craig Raw's pinned key fingerprint
3. **Checksum Verification**: Verifies the DMG's SHA-256 checksum against the signed manifest
4. **Installation**: Mounts the DMG, checks for existing installations, and installs to /Applications
5. **Code Signature Verification**: Verifies the installed app's macOS code signature
6. **Cleanup**: Unmounts the DMG and removes temporary files

## Automatic Version Detection

The script automatically detects:

1. The latest available version of Sparrow Wallet from GitHub
2. Your Mac's architecture (Intel or Apple Silicon)

No manual configuration is needed! The script will always download the latest compatible version for your system.

## Security Considerations

- The script verifies both the manifest signature and the DMG file checksum
- PGP keys are fetched from keybase.io for Craig Raw (Sparrow Wallet developer)
- **PGP key fingerprint is pinned** — the script rejects signatures from any key other than Craig Raw's known fingerprint (`D4D0D3202FC06849A257B38DE94618334C674B40`)
- **macOS code signature verification** — after installation, the script verifies the app's code signature via `codesign`
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
   sudo ./sparrow_verify.sh
   ```

3. **Sparrow Is Running**
   
   The script will detect if Sparrow is running and prompt you to close it before continuing.

## Example Output of a Successful Installation

```
./sparrow_verify.sh
Working in temporary directory: /var/folders/p8/vn70_dzs4mj0bl5y5llp258r0000gn/T/tmp.htkd6Hir9E
Detecting latest Sparrow Wallet version...
Latest version detected: 2.1.3
Detected architecture: aarch64
Downloading Sparrow Wallet DMG...
########################################################################################################################################################## 100.0%
Downloading manifest file...
########################################################################################################################################################## 100.0%
Downloading manifest signature...
########################################################################################################################################################## 100.0%
Downloading developer's PGP key...
########################################################################################################################################################## 100.0%
Importing developer's PGP key...
gpg: key E94618334C674B40: "Craig Raw <craig@sparrowwallet.com>" not changed
gpg: Total number processed: 1
gpg:              unchanged: 1
Verifying manifest signature...
✅ Manifest signature verified successfully (signed by D4D0D3202FC06849A257B38DE94618334C674B40)!
Verifying DMG file against manifest...
Calculating SHA-256 checksum of downloaded file...
Checksum: 1836037fdadc9a5faf756628ac723ac10dfddf1c5ccdb6d724b26f7cddbe59c8
Expected checksum: 1836037fdadc9a5faf756628ac723ac10dfddf1c5ccdb6d724b26f7cddbe59c8
✅ DMG file checksum verified successfully!
Mounting the DMG file...
Existing Sparrow.app found, replacing...
Installing Sparrow.app to Applications folder...
Unmounting DMG...
"disk4" ejected.
Verifying macOS code signature...
✅ macOS code signature verified successfully!
✅ Sparrow Wallet 2.1.3 has been successfully installed to the Applications folder!
You can now launch Sparrow from your Applications folder or Launchpad.
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This script is provided as-is without any warranties. Always ensure you trust the source of any script before running it on your system, especially those that require elevated privileges.

---

*This project is not officially affiliated with Sparrow Wallet.*