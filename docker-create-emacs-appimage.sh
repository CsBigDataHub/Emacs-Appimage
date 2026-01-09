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

# Get current user's UID and GID for Docker
USER_ID=$(id -u)
GROUP_ID=$(id -g)
USER_NAME=$(whoami)

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
# KEY FIX: Pass USER_ID and GROUP_ID to the build script AND fix permissions at the end
CMD_STRING="pacman -Syu --noconfirm base-devel sudo wget file && \
chmod +x emacs-appimage-build.sh && \
./emacs-appimage-build.sh --uid ${USER_ID} --gid ${GROUP_ID} ${INNER_ARGS} && \
echo '=== FIXING FINAL PERMISSIONS ===' && \
chown ${USER_ID}:${GROUP_ID} ${OUTPUT} 2>/dev/null || true && \
chmod 755 ${OUTPUT} && \
ls -lah ${OUTPUT}"

echo "════════════════════════════════════════════════════════════════"
echo "Starting Docker build container..."
echo "  Version: ${APP_VERSION}"
echo "  Output:  ${OUTPUT}"
echo "  User:    ${USER_NAME} (${USER_ID}:${GROUP_ID})"
if [[ -n "${ICON_URL}" ]]; then echo "  Icon:    Custom"; fi
echo "════════════════════════════════════════════════════════════════"

# Execute the Docker command
docker run -it --rm \
    --device /dev/fuse \
    --cap-add SYS_ADMIN \
    --security-opt apparmor:unconfined \
    -v "${SCRIPT_DIR}:${BUILD_DIR}" \
    -w "${BUILD_DIR}" \
    archlinux \
    /bin/bash -c "${CMD_STRING}"

TARGET_FILE="${SCRIPT_DIR}/${OUTPUT}"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "POST-BUILD PERMISSION CHECK"
echo "════════════════════════════════════════════════════════════════"

if [[ -f "${TARGET_FILE}" ]]; then
    echo "✓ AppImage file exists: ${TARGET_FILE}"

    # Check current permissions and ownership
    CURRENT_PERMS=$(stat -c '%a' "${TARGET_FILE}" 2>/dev/null || stat -f '%p' "${TARGET_FILE}" 2>/dev/null || echo "unknown")
    CURRENT_OWNER=$(stat -c '%U:%G' "${TARGET_FILE}" 2>/dev/null || stat -f '%Su:%Sg' "${TARGET_FILE}" 2>/dev/null || echo "unknown")

    echo "  Current: ${CURRENT_PERMS} ${CURRENT_OWNER}"
    echo "  Expected: 755 ${USER_NAME}:${USER_NAME}"

    # Double-check ownership - if Docker failed to chown, we need sudo
    if [[ ! -O "${TARGET_FILE}" ]]; then
        echo ""
        echo "⚠ WARNING: File is still owned by root!"
        echo "  This happens when Docker's internal chown fails."
        echo "  We need sudo to fix this..."
        echo ""

        if sudo chown "${USER_ID}:${GROUP_ID}" "${TARGET_FILE}" && sudo chmod 755 "${TARGET_FILE}"; then
            echo "✓ Permissions fixed with sudo"
        else
            echo "✗ Failed to fix permissions even with sudo!"
            echo "  Try manually: sudo chown ${USER_NAME}:${USER_NAME} ${TARGET_FILE}"
            exit 1
        fi
    fi

    # Final verification
    if [[ -r "${TARGET_FILE}" ]] && [[ -x "${TARGET_FILE}" ]]; then
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo "✓✓✓ BUILD SUCCESSFUL ✓✓✓"
        echo "════════════════════════════════════════════════════════════════"
        echo "AppImage: ${TARGET_FILE}"
        echo ""
        echo "NEXT STEPS FOR ICON:"
        echo "1. Clear icon cache:"
        echo "   rm -rf ~/.cache/thumbnails/*"
        echo "   rm -rf ~/.cache/icon-cache.kcache"
        echo ""
        echo "2. Update icon cache:"
        echo "   gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor/ 2>/dev/null || true"
        echo ""
        echo "3. Move AppImage to GearLever location:"
        echo "   mv \"${TARGET_FILE}\" ~/AppImages/"
        echo ""
        echo "4. Then add it in GearLever"
        echo "   (or restart GearLever: killall gearlever && gearlever &)"
        echo "════════════════════════════════════════════════════════════════"
    else
        echo "✗ File exists but is not readable/executable!"
        ls -lah "${TARGET_FILE}"
        exit 1
    fi
else
    echo "✗ Error: Build failed or output file not found."
    echo "Expected: ${TARGET_FILE}"
    echo ""
    echo "Files in build directory:"
    ls -lah "${SCRIPT_DIR}"
    exit 1
fi
