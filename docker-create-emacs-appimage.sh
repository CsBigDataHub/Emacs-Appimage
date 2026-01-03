#!/bin/bash

# Wrapper script for building Emacs AppImage in Docker
# Fixes FUSE issues and simplifies dependency management

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
# Only pass output if it differs from default to let inner script handle logic
if [[ "${OUTPUT}" != "emacs-${APP_VERSION}-x86_64.AppImage" ]]; then
    INNER_ARGS="${INNER_ARGS} --output \"${OUTPUT}\""
fi

# Build the command string to run inside the container.
# 1. Install ONLY the bootstrap tools (sudo, wget, base-devel).
#    The inner script (Step 1) will handle the specific library dependencies.
# 2. Make the build script executable.
# 3. Run the build script with the forwarded arguments.
CMD_STRING="pacman -Syu --noconfirm base-devel sudo wget && \
chmod +x build-emacs-appimage.sh && \
./build-emacs-appimage.sh ${INNER_ARGS}"

echo "Starting Docker build container..."
echo "  Version: ${APP_VERSION}"
echo "  Output:  ${OUTPUT}"
if [[ -n "${ICON_URL}" ]]; then echo "  Icon:    Custom"; fi

# Execute the Docker command
# --device /dev/fuse: REQUIRED for AppImage to mount itself
# --cap-add SYS_ADMIN: REQUIRED for FUSE mounting privileges
# --security-opt apparmor:unconfined: Prevents issues on Ubuntu hosts
docker run -it --rm \
    --device /dev/fuse \
    --cap-add SYS_ADMIN \
    --security-opt apparmor:unconfined \
    -v "${SCRIPT_DIR}:${BUILD_DIR}" \
    -w "${BUILD_DIR}" \
    archlinux \
    /bin/bash -c "${CMD_STRING}"

# Check if the build produced an output
if [[ -f "${SCRIPT_DIR}/${OUTPUT}" ]]; then
    echo "----------------------------------------------------------------"
    echo "Build successful!"
    echo "AppImage available at: ${SCRIPT_DIR}/${OUTPUT}"
    echo "----------------------------------------------------------------"
else
    echo "Error: Output file not found. Build may have failed."
    exit 1
fi
