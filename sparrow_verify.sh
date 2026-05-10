#!/bin/bash
set -euo pipefail

# Script to download, verify, and install Sparrow Wallet
# Usage: ./sparrow_verify.sh [--debug] [--insecure-skip-all-verification]

DEBUG=0
SKIP_ALL_VERIFICATION=0
DEPRECATED_SKIP_VERIFY_USED=0
USE_SUDO=0
SWAP_IN_PROGRESS=0

TEMP_DIR=""
GNUPGHOME_DIR=""
MOUNT_DIR=""
STAGE_PARENT=""
STAGE_PATH=""
BACKUP_PATH=""
DEST_PATH="/Applications/Sparrow.app"
EXPECTED_FINGERPRINT="D4D0D3202FC06849A257B38DE94618334C674B40"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--debug] [--insecure-skip-all-verification]

Downloads, verifies, and installs Sparrow Wallet for macOS.

Options:
  --debug                              Enable detailed debugging information
  --insecure-skip-all-verification     Skip PGP signature and SHA-256 checksum verification
  --skip-verify                        Deprecated alias for --insecure-skip-all-verification
  -h, --help                           Show this help message
EOF
}

debug() {
    if [[ $DEBUG -eq 1 ]]; then
        echo "[DEBUG] $1"
    fi
}

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

run_install_cmd() {
    if [[ $USE_SUDO -eq 1 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

restore_backup() {
    if [[ $SWAP_IN_PROGRESS -ne 1 ]]; then
        return
    fi

    echo "Restoring previous Sparrow.app after failed install..."
    if [[ -e "$DEST_PATH" || -L "$DEST_PATH" ]]; then
        run_install_cmd rm -rf "$DEST_PATH" || true
    fi

    if [[ -n "$BACKUP_PATH" && ( -e "$BACKUP_PATH" || -L "$BACKUP_PATH" ) ]]; then
        run_install_cmd mv "$BACKUP_PATH" "$DEST_PATH" || true
    fi
}

cleanup() {
    local exit_code=$?
    set +e
    trap - EXIT INT TERM

    if [[ -n "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi

    restore_backup

    if [[ -n "$STAGE_PARENT" && -d "$STAGE_PARENT" ]]; then
        run_install_cmd rm -rf "$STAGE_PARENT" || true
    fi

    if [[ -n "$GNUPGHOME_DIR" ]]; then
        rm -rf "$GNUPGHOME_DIR" || true
    fi

    if [[ -n "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" || true
    fi

    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

parse_args() {
    local arg

    for arg in "$@"; do
        case "$arg" in
            --debug)
                DEBUG=1
                echo "Debug mode enabled"
                ;;
            --insecure-skip-all-verification)
                SKIP_ALL_VERIFICATION=1
                ;;
            --skip-verify)
                SKIP_ALL_VERIFICATION=1
                DEPRECATED_SKIP_VERIFY_USED=1
                echo "WARNING: --skip-verify is deprecated; use --insecure-skip-all-verification." >&2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                exit 2
                ;;
        esac
    done
}

require_macos_and_detect_arch() {
    local os_name
    local machine_arch

    os_name=$(uname -s)
    if [[ "$os_name" != "Darwin" ]]; then
        error_exit "This installer only supports macOS (Darwin). Detected: $os_name"
    fi

    machine_arch=$(uname -m)
    case "$machine_arch" in
        arm64)
            ARCH="aarch64"
            ;;
        x86_64)
            ARCH="x86_64"
            ;;
        *)
            error_exit "Unsupported Mac architecture: $machine_arch"
            ;;
    esac
}

check_command() {
    local command_name=$1
    local install_hint=${2:-}

    if ! command -v "$command_name" >/dev/null 2>&1; then
        if [[ -n "$install_hint" ]]; then
            echo "$command_name is not installed. $install_hint" >&2
        else
            echo "$command_name is not installed or is not in PATH." >&2
        fi
        return 1
    fi

    return 0
}

check_dependencies() {
    local missing_deps=0
    local required_commands
    local command_name

    required_commands="curl hdiutil codesign shasum awk sed grep pgrep mktemp"
    for command_name in $required_commands; do
        if ! check_command "$command_name"; then
            missing_deps=1
        fi
    done

    if [[ $SKIP_ALL_VERIFICATION -eq 0 ]]; then
        if ! check_command "gpg" "Install it with: brew install gnupg"; then
            missing_deps=1
        fi
    fi

    if [[ $DEBUG -eq 1 ]]; then
        if ! check_command "xxd"; then
            missing_deps=1
        fi
    fi

    if [[ ! -x /usr/libexec/PlistBuddy ]] && ! command -v python3 >/dev/null 2>&1; then
        echo "Either /usr/libexec/PlistBuddy or python3 is required to parse hdiutil plist output." >&2
        missing_deps=1
    fi

    if [[ $missing_deps -eq 1 ]]; then
        echo "Please install the missing dependencies and try again." >&2
        if [[ $SKIP_ALL_VERIFICATION -eq 0 ]]; then
            echo "Do not bypass verification unless you explicitly accept the risk with --insecure-skip-all-verification." >&2
        fi
        exit 1
    fi
}

confirm_insecure_skip() {
    local response

    if [[ $SKIP_ALL_VERIFICATION -ne 1 ]]; then
        return
    fi

    echo "WARNING: PGP signature verification and SHA-256 checksum verification will be skipped." >&2
    echo "Only macOS code-signature verification will remain, and a code-signature failure will stop the install." >&2

    if [[ $DEPRECATED_SKIP_VERIFY_USED -eq 1 ]]; then
        echo "WARNING: --skip-verify still works as a deprecated alias, but it now skips both PGP and checksum verification." >&2
    fi

    if [[ ! -t 0 ]]; then
        error_exit "--insecure-skip-all-verification requires interactive confirmation, but stdin is not a TTY."
    fi

    if ! read -r -p "Type INSECURE to continue without PGP and checksum verification: " response; then
        error_exit "Failed to read confirmation."
    fi

    if [[ "$response" != "INSECURE" ]]; then
        error_exit "Confirmation did not match. Aborting."
    fi
}

create_working_directory() {
    TEMP_DIR=$(mktemp -d) || error_exit "Failed to create temporary directory."
    cd "$TEMP_DIR" || error_exit "Failed to enter temporary directory: $TEMP_DIR"
    echo "Working in temporary directory: $TEMP_DIR"
}

curl_latest_release_json() {
    curl -fsSL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 60 \
        --proto '=https' \
        --proto-redir '=https' \
        "https://api.github.com/repos/sparrowwallet/sparrow/releases/latest"
}

download_file() {
    local url=$1
    local output_path=$2
    local description=$3

    echo "Downloading $description..."
    if ! curl -fL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --proto '=https' \
        --proto-redir '=https' \
        --progress-bar \
        -o "$output_path" \
        "$url"; then
        error_exit "Error downloading $description"
    fi
}

extract_version() {
    local latest_version_info=$1
    local version=""

    if command -v python3 >/dev/null 2>&1; then
        version=$(printf '%s' "$latest_version_info" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", ""))' 2>/dev/null || true)
    fi

    if [[ -z "$version" ]]; then
        version=$(printf '%s' "$latest_version_info" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed -n '1p' || true)
    fi

    if [[ -z "$version" ]]; then
        return 1
    fi

    if [[ ! "$version" =~ ^v?[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
        echo "Unexpected release tag format: $version" >&2
        return 1
    fi

    printf '%s\n' "$version"
}

check_nonempty_file() {
    local file_path=$1
    local description=$2

    if [[ ! -s "$file_path" ]]; then
        error_exit "$description is empty or was not downloaded"
    fi
}

setup_gpg_home() {
    GNUPGHOME_DIR=$(mktemp -d) || error_exit "Failed to create temporary GnuPG home."
    chmod 700 "$GNUPGHOME_DIR" || error_exit "Failed to secure temporary GnuPG home."
    export GNUPGHOME="$GNUPGHOME_DIR"
}

import_and_validate_pgp_key() {
    local import_output
    local imported_primary_fingerprints

    setup_gpg_home

    echo "Importing developer's PGP key..."
    if ! import_output=$(gpg --batch --import "$KEY_FILE" 2>&1); then
        echo "$import_output" >&2
        error_exit "Failed to import developer's PGP key."
    fi
    debug "$import_output"

    imported_primary_fingerprints=$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '
        $1 == "pub" { want_fpr = 1; next }
        want_fpr && $1 == "fpr" { print toupper($10); want_fpr = 0 }
    ')

    if ! printf '%s\n' "$imported_primary_fingerprints" | grep -qx "$EXPECTED_FINGERPRINT"; then
        echo "Imported primary fingerprints:" >&2
        printf '%s\n' "$imported_primary_fingerprints" >&2
        error_exit "Imported PGP key did not match expected fingerprint: $EXPECTED_FINGERPRINT"
    fi

    echo "PGP key fingerprint verified: $EXPECTED_FINGERPRINT"
}

verify_manifest_signature() {
    local verification_result
    local valid_primary_fingerprints
    local valid_count
    local signing_primary_fingerprint

    echo "Verifying manifest signature..."
    if ! verification_result=$(gpg --batch --status-fd 1 --verify "$MANIFEST_SIG_FILE" "$MANIFEST_FILE" 2>&1); then
        echo "$verification_result" >&2
        error_exit "Manifest signature verification failed. Cannot verify the authenticity of the download."
    fi

    valid_primary_fingerprints=$(printf '%s\n' "$verification_result" | awk '
        $1 == "[GNUPG:]" && $2 == "VALIDSIG" && $12 != "" { print toupper($12) }
    ')
    valid_count=$(printf '%s\n' "$valid_primary_fingerprints" | sed '/^$/d' | wc -l | tr -d '[:space:]')

    if [[ "$valid_count" != "1" ]]; then
        echo "$verification_result" >&2
        error_exit "Expected exactly one VALIDSIG primary fingerprint, found $valid_count."
    fi

    signing_primary_fingerprint=$(printf '%s\n' "$valid_primary_fingerprints" | sed -n '1p')
    if [[ ! "$signing_primary_fingerprint" =~ ^[A-F0-9]{40}$ ]]; then
        echo "$verification_result" >&2
        error_exit "Invalid VALIDSIG primary fingerprint: $signing_primary_fingerprint"
    fi

    if [[ "$signing_primary_fingerprint" != "$EXPECTED_FINGERPRINT" ]]; then
        echo "$verification_result" >&2
        error_exit "Manifest was signed by unexpected primary key $signing_primary_fingerprint. Expected: $EXPECTED_FINGERPRINT"
    fi

    echo "Manifest signature verified successfully (signed by $EXPECTED_FINGERPRINT)."
}

extract_expected_checksum() {
    local manifest_path=$1
    local target_filename=$2
    local matches
    local match_count
    local checksum

    matches=$(awk -v target="$target_filename" '
        NF >= 2 {
            filename = $2
            sub(/^\*/, "", filename)
            if (filename == target) {
                print $1
            }
        }
    ' "$manifest_path")

    match_count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    if [[ "$match_count" != "1" ]]; then
        error_exit "Expected exactly one checksum match for $target_filename in manifest, found $match_count."
    fi

    checksum=$(printf '%s\n' "$matches" | sed '/^$/d' | sed -n '1p')
    if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
        error_exit "Manifest checksum for $target_filename is not exactly 64 lowercase hex characters: $checksum"
    fi

    printf '%s\n' "$checksum"
}

verify_dmg_checksum() {
    local downloaded_checksum
    local expected_checksum

    echo "Verifying DMG file against manifest..."
    echo "Calculating SHA-256 checksum of downloaded file..."

    if ! downloaded_checksum=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}'); then
        error_exit "Failed to calculate SHA-256 checksum for $DMG_FILE"
    fi

    if [[ ! "$downloaded_checksum" =~ ^[0-9a-f]{64}$ ]]; then
        error_exit "Calculated checksum is not a valid lowercase SHA-256 digest: $downloaded_checksum"
    fi

    expected_checksum=$(extract_expected_checksum "$MANIFEST_FILE" "$DMG_FILE")

    echo "Checksum: $downloaded_checksum"
    echo "Expected checksum: $expected_checksum"

    if [[ "$downloaded_checksum" != "$expected_checksum" ]]; then
        error_exit "Checksum verification failed. The downloaded file may be corrupted or tampered with."
    fi

    echo "DMG file checksum verified successfully."
}

debug_verification_files() {
    if [[ $DEBUG -ne 1 ]]; then
        return
    fi

    echo "Manifest content:"
    cat "$MANIFEST_FILE"
    echo ""
    echo "Manifest signature (first 100 bytes):"
    xxd -l 100 "$MANIFEST_SIG_FILE"
    echo "File sizes:"
    ls -la "$DMG_FILE" "$MANIFEST_FILE" "$MANIFEST_SIG_FILE" "$KEY_FILE"
}

parse_mount_point_with_plistbuddy() {
    local plist_path=$1
    local index
    local mount_point

    for ((index = 0; index < 50; index++)); do
        mount_point=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$plist_path" 2>/dev/null || true)
        if [[ -n "$mount_point" ]]; then
            printf '%s\n' "$mount_point"
            return 0
        fi
    done

    return 1
}

parse_mount_point_with_python() {
    local plist_path=$1

    python3 -c '
import plistlib
import sys

with open(sys.argv[1], "rb") as plist_file:
    data = plistlib.load(plist_file)

for entity in data.get("system-entities", []):
    mount_point = entity.get("mount-point")
    if mount_point:
        print(mount_point)
        sys.exit(0)

sys.exit(1)
' "$plist_path"
}

parse_mount_point() {
    local plist_path=$1

    if [[ -x /usr/libexec/PlistBuddy ]]; then
        parse_mount_point_with_plistbuddy "$plist_path"
        return
    fi

    parse_mount_point_with_python "$plist_path"
}

mount_dmg() {
    local attach_plist

    echo "Mounting the DMG file..."
    attach_plist="$TEMP_DIR/hdiutil-attach.plist"
    if ! hdiutil attach -plist -nobrowse -noverify -noautoopen "$DMG_FILE" > "$attach_plist"; then
        error_exit "Failed to mount the DMG file."
    fi

    if ! MOUNT_DIR=$(parse_mount_point "$attach_plist"); then
        error_exit "Failed to find the DMG mount point in hdiutil plist output."
    fi

    if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
        error_exit "DMG mount point is invalid: $MOUNT_DIR"
    fi

    debug "DMG mounted at: $MOUNT_DIR"
}

detach_dmg() {
    if [[ -z "$MOUNT_DIR" ]]; then
        return
    fi

    echo "Unmounting DMG..."
    hdiutil detach "$MOUNT_DIR" -force
    MOUNT_DIR=""
}

verify_codesign_hard() {
    local app_path=$1
    local context=$2
    local output

    echo "Verifying macOS code signature for $context..."
    if output=$(codesign --verify --deep --strict "$app_path" 2>&1); then
        echo "macOS code signature verified successfully for $context."
    else
        if [[ -n "$output" ]]; then
            echo "$output" >&2
        fi
        error_exit "macOS code signature verification failed for $context."
    fi
}

assess_gatekeeper_warn() {
    local app_path=$1
    local context=$2
    local output

    if ! command -v spctl >/dev/null 2>&1; then
        echo "Warning: spctl is not available; skipping Gatekeeper assessment for $context." >&2
        return
    fi

    echo "Assessing $context with Gatekeeper..."
    if output=$(spctl --assess --type execute --verbose=4 "$app_path" 2>&1); then
        echo "Gatekeeper assessment passed for $context."
        if [[ -n "$output" ]]; then
            echo "$output"
        fi
    else
        echo "Warning: Gatekeeper assessment failed for $context. Continuing because this can fail in development environments." >&2
        if [[ -n "$output" ]]; then
            echo "$output" >&2
        fi
    fi
}

wait_for_sparrow_to_exit() {
    if ! pgrep -x "Sparrow" >/dev/null; then
        return
    fi

    echo "Sparrow is currently running. Please close it before continuing." >&2
    if [[ ! -t 0 ]]; then
        error_exit "Sparrow is running and stdin is not a TTY, so the installer cannot prompt. Close Sparrow and run the script again."
    fi

    if ! read -r -p "Press Enter after closing Sparrow to continue, or Ctrl+C to cancel..." _; then
        error_exit "Failed to read confirmation."
    fi

    if pgrep -x "Sparrow" >/dev/null; then
        error_exit "Sparrow is still running. Please close it first."
    fi
}

prepare_install_privileges() {
    if [[ $EUID -eq 0 ]]; then
        USE_SUDO=0
        return
    fi

    if [[ -w /Applications ]]; then
        USE_SUDO=0
        return
    fi

    USE_SUDO=1
    if ! command -v sudo >/dev/null 2>&1; then
        error_exit "Administrator privileges are required to write to /Applications, but sudo is not available."
    fi

    echo "Administrator privileges are required only to write to /Applications."
    if ! sudo -v; then
        error_exit "Failed to obtain administrator privileges for /Applications."
    fi
}

create_application_stage() {
    prepare_install_privileges

    STAGE_PARENT=$(run_install_cmd mktemp -d "/Applications/.Sparrow.install.XXXXXX") || error_exit "Failed to create staging directory under /Applications."
    run_install_cmd chmod 755 "$STAGE_PARENT" || error_exit "Failed to set permissions on staging directory."
    STAGE_PATH="$STAGE_PARENT/Sparrow.app"

    echo "Staging Sparrow.app under /Applications..."
    if ! run_install_cmd cp -R "$MOUNT_DIR/Sparrow.app" "$STAGE_PARENT/"; then
        error_exit "Failed to stage Sparrow.app under /Applications."
    fi

    if [[ ! -d "$STAGE_PATH" ]]; then
        error_exit "Staged Sparrow.app was not created at $STAGE_PATH."
    fi
}

swap_staged_app_into_place() {
    local timestamp

    timestamp=$(date +%Y%m%d%H%M%S)
    BACKUP_PATH="/Applications/.Sparrow.app.backup.$timestamp.$$"

    if [[ -e "$DEST_PATH" || -L "$DEST_PATH" ]]; then
        echo "Existing Sparrow.app found; moving it to a temporary backup..."
        if ! run_install_cmd mv "$DEST_PATH" "$BACKUP_PATH"; then
            error_exit "Failed to move existing Sparrow.app to backup."
        fi
    fi

    SWAP_IN_PROGRESS=1

    echo "Installing staged Sparrow.app to Applications folder..."
    if ! run_install_cmd mv "$STAGE_PATH" "$DEST_PATH"; then
        error_exit "Failed to move staged Sparrow.app into place."
    fi

    if [[ -n "$STAGE_PARENT" && -d "$STAGE_PARENT" ]]; then
        run_install_cmd rmdir "$STAGE_PARENT" 2>/dev/null || true
        STAGE_PARENT=""
    fi
}

finish_successful_swap() {
    if [[ -n "$BACKUP_PATH" && ( -e "$BACKUP_PATH" || -L "$BACKUP_PATH" ) ]]; then
        run_install_cmd rm -rf "$BACKUP_PATH"
    fi

    BACKUP_PATH=""
    SWAP_IN_PROGRESS=0
}

parse_args "$@"
require_macos_and_detect_arch
check_dependencies
confirm_insecure_skip
create_working_directory

echo "Detecting latest Sparrow Wallet version..."
if ! LATEST_VERSION_INFO=$(curl_latest_release_json); then
    error_exit "Failed to fetch latest version information from GitHub"
fi

if ! VERSION=$(extract_version "$LATEST_VERSION_INFO"); then
    error_exit "Failed to extract a valid version from GitHub API response"
fi

ASSET_VERSION=${VERSION#v}
echo "Latest version detected: $VERSION"
echo "Detected architecture: $ARCH"

DMG_FILE="Sparrow-$ASSET_VERSION-$ARCH.dmg"
MANIFEST_FILE="sparrow-$ASSET_VERSION-manifest.txt"
MANIFEST_SIG_FILE="$MANIFEST_FILE.asc"
KEY_FILE="pgp_keys.asc"

DMG_URL="https://github.com/sparrowwallet/sparrow/releases/download/$VERSION/$DMG_FILE"
MANIFEST_URL="https://github.com/sparrowwallet/sparrow/releases/download/$VERSION/$MANIFEST_FILE"
MANIFEST_SIG_URL="https://github.com/sparrowwallet/sparrow/releases/download/$VERSION/$MANIFEST_SIG_FILE"
KEY_URL="https://keybase.io/craigraw/pgp_keys.asc"

debug "DMG URL: $DMG_URL"
debug "Manifest URL: $MANIFEST_URL"
debug "Manifest signature URL: $MANIFEST_SIG_URL"
debug "Key URL: $KEY_URL"

download_file "$DMG_URL" "$DMG_FILE" "Sparrow Wallet DMG"
check_nonempty_file "$DMG_FILE" "DMG file"

if [[ $SKIP_ALL_VERIFICATION -eq 0 ]]; then
    download_file "$MANIFEST_URL" "$MANIFEST_FILE" "manifest file"
    download_file "$MANIFEST_SIG_URL" "$MANIFEST_SIG_FILE" "manifest signature"
    download_file "$KEY_URL" "$KEY_FILE" "developer's PGP key"

    check_nonempty_file "$MANIFEST_FILE" "Manifest file"
    check_nonempty_file "$MANIFEST_SIG_FILE" "Manifest signature file"
    check_nonempty_file "$KEY_FILE" "PGP key file"

    debug_verification_files
    import_and_validate_pgp_key
    verify_manifest_signature
    verify_dmg_checksum
else
    echo "WARNING: PGP signature and SHA-256 checksum verification were skipped." >&2
    echo "The authenticity of this download is not confirmed by the signed manifest." >&2
fi

mount_dmg

if [[ ! -d "$MOUNT_DIR/Sparrow.app" ]]; then
    error_exit "Could not find Sparrow.app in the mounted DMG."
fi

verify_codesign_hard "$MOUNT_DIR/Sparrow.app" "mounted Sparrow.app"
assess_gatekeeper_warn "$MOUNT_DIR/Sparrow.app" "mounted Sparrow.app"

wait_for_sparrow_to_exit
create_application_stage
swap_staged_app_into_place

verify_codesign_hard "$DEST_PATH" "installed Sparrow.app"
finish_successful_swap
detach_dmg

echo "Sparrow Wallet $VERSION has been successfully installed to the Applications folder."
echo "You can now launch Sparrow from your Applications folder or Launchpad."
