#!/bin/bash

# Fix AppImage Permissions Script
# Use this if GearLever shows "Operation not permitted" errors

set -e

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <path-to-appimage>"
    echo ""
    echo "Example:"
    echo "  $0 emacs-30.2-x86_64.AppImage"
    echo "  $0 ~/git-repos/emacs-app-image-builder/emacs-30.2-x86_64.AppImage"
    exit 1
fi

APPIMAGE="$1"

if [[ ! -f "${APPIMAGE}" ]]; then
    echo "Error: File not found: ${APPIMAGE}"
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "AppImage Permission Diagnostic & Fix"
echo "════════════════════════════════════════════════════════════════"
echo "File: ${APPIMAGE}"
echo ""

# Get current user info
USER_NAME=$(whoami)
USER_ID=$(id -u)
GROUP_ID=$(id -g)

echo "Your user: ${USER_NAME} (${USER_ID}:${GROUP_ID})"
echo ""

# Check current state
echo "Current file status:"
ls -lah "${APPIMAGE}"
echo ""

# Get owner
FILE_OWNER=$(stat -c '%U' "${APPIMAGE}" 2>/dev/null || stat -f '%Su' "${APPIMAGE}" 2>/dev/null || echo "unknown")
FILE_GROUP=$(stat -c '%G' "${APPIMAGE}" 2>/dev/null || stat -f '%Sg' "${APPIMAGE}" 2>/dev/null || echo "unknown")
FILE_PERMS=$(stat -c '%a' "${APPIMAGE}" 2>/dev/null || stat -f '%Lp' "${APPIMAGE}" 2>/dev/null || echo "unknown")

echo "Owner: ${FILE_OWNER}:${FILE_GROUP}"
echo "Permissions: ${FILE_PERMS}"
echo ""

# Check if readable/executable
if [[ -r "${APPIMAGE}" ]] && [[ -x "${APPIMAGE}" ]]; then
    echo "✓ File is readable and executable by you"
    echo ""
    echo "If GearLever still can't access it, the issue might be:"
    echo "1. SELinux/AppArmor restrictions"
    echo "2. GearLever running as Flatpak with limited permissions"
    echo ""
    echo "Try moving the file to ~/AppImages/ directory:"
    echo "  mkdir -p ~/AppImages"
    echo "  cp \"${APPIMAGE}\" ~/AppImages/"
    echo ""
    exit 0
fi

echo "✗ File has permission issues!"
echo ""

# Check if we own it
if [[ "${FILE_OWNER}" == "${USER_NAME}" ]]; then
    echo "You own the file, but permissions are wrong."
    echo "Fixing permissions (no sudo needed)..."
    chmod 755 "${APPIMAGE}"
    echo "✓ Fixed!"
else
    echo "File is owned by: ${FILE_OWNER}"
    echo "You need sudo to take ownership..."
    echo ""
    read -p "Fix with sudo? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo chown "${USER_ID}:${GROUP_ID}" "${APPIMAGE}"
        sudo chmod 755 "${APPIMAGE}"
        echo "✓ Fixed!"
    else
        echo "Skipped. File remains owned by ${FILE_OWNER}"
        exit 1
    fi
fi

echo ""
echo "Final status:"
ls -lah "${APPIMAGE}"
echo ""

# Test if it works
if [[ -r "${APPIMAGE}" ]] && [[ -x "${APPIMAGE}" ]]; then
    echo "✓ File is now readable and executable!"
    echo ""
    echo "Now you can add it to GearLever:"
    echo "  mkdir -p ~/AppImages"
    echo "  mv \"${APPIMAGE}\" ~/AppImages/"
else
    echo "✗ Something is still wrong with permissions"
    stat "${APPIMAGE}"
fi
