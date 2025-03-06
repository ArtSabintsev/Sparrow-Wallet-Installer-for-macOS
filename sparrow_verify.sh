#!/bin/bash

# Script to download, verify, and install Sparrow Wallet
# Usage: ./sparrow_verify.sh [--debug] [--skip-verify]

# Check for flags
DEBUG=0
SKIP_VERIFY=0

for arg in "$@"; do
  case $arg in
    --debug)
      DEBUG=1
      echo "Debug mode enabled"
      ;;
    --skip-verify)
      SKIP_VERIFY=1
      echo "WARNING: Skipping signature verification (not recommended)"
      ;;
  esac
done

# Debug function
debug() {
    if [[ $DEBUG -eq 1 ]]; then
        echo "[DEBUG] $1"
    fi
}

# Exit with error
error_exit() {
    echo "ERROR: $1"
    cd ~
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    exit 1
}

# Check for dependencies
check_dependencies() {
    local missing_deps=0
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        echo "curl is not installed. Please install it with: brew install curl"
        missing_deps=1
    fi
    
    # Check for gpg only if we're not skipping verification
    if [[ $SKIP_VERIFY -eq 0 ]]; then
        if ! command -v gpg &> /dev/null; then
            echo "gpg is not installed. Please install it with: brew install gnupg"
            missing_deps=1
        fi
    fi
    
    if [[ $missing_deps -eq 1 ]]; then
        echo "Please install the missing dependencies and try again."
        if [[ $SKIP_VERIFY -eq 0 ]]; then
            echo "Alternatively, you can run with --skip-verify to download without verification."
            echo "(Not recommended for security reasons)"
        fi
        exit 1
    fi
}

# Check dependencies
check_dependencies

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
echo "Working in temporary directory: $TEMP_DIR"

# Detect the latest version from GitHub API
echo "Detecting latest Sparrow Wallet version..."
LATEST_VERSION_INFO=$(curl -s https://api.github.com/repos/sparrowwallet/sparrow/releases/latest)
if [ $? -ne 0 ]; then
    error_exit "Failed to fetch latest version information from GitHub"
fi

VERSION=$(echo "$LATEST_VERSION_INFO" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    error_exit "Failed to extract version information from GitHub API response"
fi

echo "Latest version detected: $VERSION"

# Detect architecture
ARCH="aarch64"
if [[ $(uname -m) == "x86_64" ]]; then
    ARCH="x86_64"
fi
echo "Detected architecture: $ARCH"

# Set filenames
DMG_FILE="Sparrow-$VERSION-$ARCH.dmg"
MANIFEST_FILE="sparrow-$VERSION-manifest.txt"
MANIFEST_SIG_FILE="$MANIFEST_FILE.asc"
KEY_FILE="pgp_keys.asc"

# URLs
DMG_URL="https://github.com/sparrowwallet/sparrow/releases/download/$VERSION/$DMG_FILE"
MANIFEST_URL="https://github.com/sparrowwallet/sparrow/releases/download/$VERSION/$MANIFEST_FILE"
MANIFEST_SIG_URL="https://github.com/sparrowwallet/sparrow/releases/download/$VERSION/$MANIFEST_SIG_FILE"
KEY_URL="https://keybase.io/craigraw/pgp_keys.asc"

# Debug URLs
debug "DMG URL: $DMG_URL"
debug "MANIFEST URL: $MANIFEST_URL"
debug "MANIFEST SIG URL: $MANIFEST_SIG_URL"
debug "KEY URL: $KEY_URL"

# Download DMG
echo "Downloading Sparrow Wallet DMG..."
if ! curl -L --progress-bar -o "$DMG_FILE" "$DMG_URL"; then
    error_exit "Error downloading DMG file"
fi

# Only download verification files if we're going to verify
if [[ $SKIP_VERIFY -eq 0 ]]; then
    echo "Downloading manifest file..."
    if ! curl -L --progress-bar -o "$MANIFEST_FILE" "$MANIFEST_URL"; then
        error_exit "Error downloading manifest file"
    fi

    echo "Downloading manifest signature..."
    if ! curl -L --progress-bar -o "$MANIFEST_SIG_FILE" "$MANIFEST_SIG_URL"; then
        error_exit "Error downloading manifest signature"
    fi

    echo "Downloading developer's PGP key..."
    if ! curl -L --progress-bar -o "$KEY_FILE" "$KEY_URL"; then
        error_exit "Error downloading PGP key"
    fi
fi

# Check if DMG was downloaded successfully and has content
if [ ! -s "$DMG_FILE" ]; then
    error_exit "DMG file is empty or not downloaded"
fi

# Verify using manifest if not skipped
if [[ $SKIP_VERIFY -eq 0 ]]; then
    # Check if verification files were downloaded successfully
    if [ ! -s "$MANIFEST_FILE" ]; then
        error_exit "Manifest file is empty or not downloaded"
    fi

    if [ ! -s "$MANIFEST_SIG_FILE" ]; then
        error_exit "Manifest signature file is empty or not downloaded"
    fi

    if [ ! -s "$KEY_FILE" ]; then
        error_exit "PGP key file is empty or not downloaded"
    fi

    # Debug file content
    if [[ $DEBUG -eq 1 ]]; then
        echo "Manifest content:"
        cat "$MANIFEST_FILE"
        echo ""
        echo "Manifest signature (first 100 bytes):"
        xxd -l 100 "$MANIFEST_SIG_FILE"
        echo "File sizes:"
        ls -la "$DMG_FILE" "$MANIFEST_FILE" "$MANIFEST_SIG_FILE" "$KEY_FILE"
    fi

    # Import the developer's PGP key
    echo "Importing developer's PGP key..."
    gpg --import "$KEY_FILE"

    # Verify the manifest signature
    echo "Verifying manifest signature..."
    VERIFICATION_RESULT=$(gpg --verify "$MANIFEST_SIG_FILE" "$MANIFEST_FILE" 2>&1)
    VERIFICATION_STATUS=$?

    if [[ $VERIFICATION_STATUS -ne 0 ]]; then
        echo "$VERIFICATION_RESULT"
        error_exit "Manifest signature verification failed! Cannot verify the authenticity of the download."
    fi
    
    echo "✅ Manifest signature verified successfully!"
    
    # Now verify the DMG file against the manifest
    echo "Verifying DMG file against manifest..."
    
    # Calculate the checksum of the downloaded DMG
    echo "Calculating SHA-256 checksum of downloaded file..."
    DOWNLOADED_CHECKSUM=$(shasum -a 256 "$DMG_FILE" | cut -d' ' -f1)
    echo "Checksum: $DOWNLOADED_CHECKSUM"
    
    # Extract the expected checksum from the manifest
    EXPECTED_CHECKSUM=$(grep -i "$DMG_FILE" "$MANIFEST_FILE" | awk '{print $1}')
    
    # If not found, try different formats that might be in the manifest
    if [ -z "$EXPECTED_CHECKSUM" ]; then
        debug "Checksum not found with exact match, trying alternative patterns"
        EXPECTED_CHECKSUM=$(grep -i "aarch64.dmg" "$MANIFEST_FILE" | awk '{print $1}')
    fi
    
    if [ -z "$EXPECTED_CHECKSUM" ]; then
        debug "Still no match, checking entire manifest content"
        cat "$MANIFEST_FILE"
        error_exit "Could not find checksum for $DMG_FILE in manifest"
    fi
    
    echo "Expected checksum: $EXPECTED_CHECKSUM"
    
    # Compare checksums
    if [[ "$DOWNLOADED_CHECKSUM" != "$EXPECTED_CHECKSUM" ]]; then
        error_exit "Checksum verification failed! The downloaded file may be corrupted or tampered with."
    fi
    
    echo "✅ DMG file checksum verified successfully!"
else
    echo "⚠️  WARNING: Verification was skipped. The authenticity of this download is not confirmed."
    echo "    For maximum security, please install gpg and run without --skip-verify."
fi

# Mount the DMG file
echo "Mounting the DMG file..."
MOUNT_DIR=$(hdiutil attach "$DMG_FILE" -nobrowse -noverify -noautoopen | grep 'Apple_HFS' | awk '{print $3}')

if [ -z "$MOUNT_DIR" ]; then
    error_exit "Failed to mount the DMG file."
fi

debug "DMG mounted at: $MOUNT_DIR"

# Check if Sparrow.app exists in the mounted DMG
if [ ! -d "$MOUNT_DIR/Sparrow.app" ]; then
    # Unmount the DMG before exiting with error
    hdiutil detach "$MOUNT_DIR" -force
    error_exit "Could not find Sparrow.app in the mounted DMG."
fi

# Destination path
DEST_PATH="/Applications/Sparrow.app"

# Check if Sparrow is currently running
if pgrep -x "Sparrow" > /dev/null; then
    echo "⚠️  Sparrow is currently running. Please close it before continuing."
    read -p "Press Enter after closing Sparrow to continue, or Ctrl+C to cancel..." 
    
    # Double-check if it's still running
    if pgrep -x "Sparrow" > /dev/null; then
        # Unmount the DMG before exiting with error
        hdiutil detach "$MOUNT_DIR" -force
        error_exit "Sparrow is still running. Please close it first."
    fi
fi

# Check if Sparrow.app already exists in Applications folder
if [ -d "$DEST_PATH" ]; then
    echo "Existing Sparrow.app found, replacing..."
    rm -rf "$DEST_PATH"
    if [ $? -ne 0 ]; then
        # Unmount the DMG before exiting with error
        hdiutil detach "$MOUNT_DIR" -force
        error_exit "Failed to remove existing Sparrow.app. You may need to run this script with sudo."
    fi
fi

# Copy Sparrow.app to Applications folder
echo "Installing Sparrow.app to Applications folder..."
cp -R "$MOUNT_DIR/Sparrow.app" "/Applications/"
if [ $? -ne 0 ]; then
    # Unmount the DMG before exiting with error
    hdiutil detach "$MOUNT_DIR" -force
    error_exit "Failed to copy Sparrow.app to Applications folder. You may need to run this script with sudo."
fi

# Unmount the DMG
echo "Unmounting DMG..."
hdiutil detach "$MOUNT_DIR" -force

# Clean up
cd ~
rm -rf "$TEMP_DIR"

echo "✅ Sparrow Wallet $VERSION has been successfully installed to the Applications folder!"
echo "You can now launch Sparrow from your Applications folder or Launchpad."