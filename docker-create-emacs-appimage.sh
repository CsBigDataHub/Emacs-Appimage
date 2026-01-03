#!/bin/bash

# Wrapper script for building Emacs AppImage in Docker
# Fixes FUSE issues, simplifies dependency management, and FIXES FILE PERMISSIONS

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/build"
OUTPUT_DIR="$(pwd)"
APP_VERSION="30.2"
OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"

# Parse command line arguments
ICON_URL=""
while [[ $# -gt 0 ]]; do
    case $1 in
    --icon | -i)
        ICON_URL="$2"
        shift 2
        ;;
    --version | -v)
        APP_VERSION="$2"
        OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"
        shift 2
        ;;
    --output | -o)
        OUTPUT="$2"
        shift 2
        ;;
    --help | -h)
        echo "Usage: $0 [--icon ICON_URL] [--version VERSION] [--output OUTPUT]"
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Prepare arguments to pass to the inner build script
INNER_ARGS=""
if [[ -n "${ICON_URL}" ]]; then
    INNER_ARGS="${INNER_ARGS} --icon \"${ICON_URL}\""
fi
if [[ "${APP_VERSION}" != "30.2" ]]; then
    INNER_ARGS="${INNER_ARGS} --version \"${APP_VERSION}\""
fi
# Only pass output if it differs from default to avoid confusion
if [[ "${OUTPUT}" != "emacs-${APP_VERSION}-x86_64.AppImage" ]]; then
    INNER_ARGS="${INNER_ARGS} --output \"${OUTPUT}\""
fi

# Build the command string to run inside the container.
CMD_STRING="pacman -Syu --noconfirm base-devel sudo wget file && \
chmod +x build-emacs-appimage.sh && \
./build-emacs-appimage.sh ${INNER_ARGS}"

echo "Starting Docker build container..."
echo "  Version: ${APP_VERSION}"
echo "  Output:  ${OUTPUT}"
if [[ -n "${ICON_URL}" ]]; then echo "  Icon:    Custom"; fi

# Execute the Docker command
docker run -it --rm \
    --device /dev/fuse \
    --cap-add SYS_ADMIN \
    --security-opt apparmor:unconfined \
    -v "${SCRIPT_DIR}:${BUILD_DIR}" \
    -w "${BUILD_DIR}" \
    archlinux \
    /bin/bash -c "${CMD_STRING}"

# ----------------------------------------------------------------
# CRITICAL FIX: RECLAIM OWNERSHIP
# ----------------------------------------------------------------
# Docker creates files as root. We must give them back to the user
# so tools like GearLever can move/read them.

TARGET_FILE="${SCRIPT_DIR}/${OUTPUT}"

if [[ -f "${TARGET_FILE}" ]]; then
    # Get current user's UID and GID
    USER_ID=$(id -u)
    GROUP_ID=$(id -g)

    # Check if we own the file. If not, SUDO grab it.
    if [[ ! -O "${TARGET_FILE}" ]]; then
        echo "----------------------------------------------------------------"
        echo "Fixing file permissions (Docker created file as root)..."
        echo "You may be asked for your sudo password."
        sudo chown "${USER_ID}:${GROUP_ID}" "${TARGET_FILE}"
        sudo chmod 755 "${TARGET_FILE}"
        echo "✓ Ownership claimed for user: $(whoami)"
    fi

    echo "----------------------------------------------------------------"
    echo "Build successful!"
    echo "AppImage available at: ${TARGET_FILE}"
    echo "----------------------------------------------------------------"
else
    echo "Error: Build failed or output file not found."
    exit 1
fi
