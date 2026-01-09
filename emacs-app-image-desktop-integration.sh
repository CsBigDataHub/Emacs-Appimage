#!/bin/bash

################################################################################
#                                                                              #
#  EMACS APPIMAGE - GEARLEVER DESKTOP INTEGRATION                              #
#                                                                              #
#  Creates two desktop entries:                                               #
#  1. Emacs - Main editor                                                     #
#  2. Emacs Client - Client mode for existing daemon                          #
#                                                                              #
#  Supports both Flatpak and standalone GearLever installations               #
#                                                                              #
################################################################################

set -euo pipefail

# Configuration
APPIMAGE_DIR="${HOME}/AppImages"
APPIMAGE_NAME="emacs-30.2-x86_64.AppImage"
APPIMAGE_PATH="${APPIMAGE_DIR}/${APPIMAGE_NAME}"
ICON_NAME="emacs-appimage"

# Desktop entry locations
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
APPLICATIONS_DIR="${XDG_DATA_HOME}/applications"
ICONS_DIR="${XDG_DATA_HOME}/icons/hicolor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Integrate Emacs AppImage with desktop using GearLever

Options:
  --appimage PATH          Path to Emacs AppImage (default: ${APPIMAGE_PATH})
  --icon-name NAME         Icon name to use (default: ${ICON_NAME})
  --uninstall              Remove desktop integration
  --help, -h               Show this help

Environment Variables:
  APPIMAGE_DIR             Directory containing AppImage (default: ~/AppImages)
  XDG_DATA_HOME            User data directory (default: ~/.local/share)

Examples:
  # Install with default settings
  $0

  # Install with custom AppImage path
  $0 --appimage /path/to/emacs.AppImage

  # Uninstall desktop integration
  $0 --uninstall

EOF
    exit 0
}

################################################################################
# GearLever Detection
################################################################################

detect_gearlever() {
    print_header "Detecting GearLever Installation"

    # Check for Flatpak version
    if command -v flatpak &>/dev/null; then
        if flatpak list | grep -q "it.mijorus.gearlever"; then
            print_success "Found GearLever (Flatpak)"
            GEARLEVER_TYPE="flatpak"
            GEARLEVER_CMD="flatpak run it.mijorus.gearlever"
            return 0
        fi
    fi

    # Check for standalone binary
    if command -v gearlever &>/dev/null; then
        print_success "Found GearLever (Standalone)"
        GEARLEVER_TYPE="standalone"
        GEARLEVER_CMD="gearlever"
        return 0
    fi

    # Check common installation paths
    for path in \
        "${HOME}/.local/bin/gearlever" \
        "/usr/local/bin/gearlever" \
        "/usr/bin/gearlever" \
        "${HOME}/bin/gearlever"; do
        if [[ -x "$path" ]]; then
            print_success "Found GearLever at: $path"
            GEARLEVER_TYPE="standalone"
            GEARLEVER_CMD="$path"
            return 0
        fi
    done

    print_warning "GearLever not found (will create desktop entries manually)"
    GEARLEVER_TYPE="none"
    GEARLEVER_CMD=""
    return 1
}

################################################################################
# AppImage Validation
################################################################################

validate_appimage() {
    print_header "Validating AppImage"

    if [[ ! -f "${APPIMAGE_PATH}" ]]; then
        print_error "AppImage not found: ${APPIMAGE_PATH}"
        print_info "Please ensure the AppImage is located at: ${APPIMAGE_PATH}"
        print_info "Or specify the path with: $0 --appimage /path/to/emacs.AppImage"
        exit 1
    fi

    if [[ ! -x "${APPIMAGE_PATH}" ]]; then
        print_warning "AppImage is not executable, fixing permissions..."
        chmod +x "${APPIMAGE_PATH}"
        print_success "Made executable: ${APPIMAGE_PATH}"
    fi

    # Test if AppImage works
    if ! "${APPIMAGE_PATH}" --version &>/dev/null; then
        print_error "AppImage failed to execute"
        print_info "Try running manually: ${APPIMAGE_PATH} --version"
        exit 1
    fi

    print_success "AppImage validated: ${APPIMAGE_PATH}"
}

################################################################################
# Icon Extraction
################################################################################

extract_icon() {
    print_header "Extracting Icon from AppImage"

    local temp_dir
    temp_dir=$(mktemp -d)

    # Extract AppImage
    print_info "Extracting AppImage to temporary directory..."
    cd "$temp_dir"
    "${APPIMAGE_PATH}" --appimage-extract >/dev/null 2>&1 || {
        print_error "Failed to extract AppImage"
        rm -rf "$temp_dir"
        return 1
    }

    # Find icon in extracted contents
    local icon_found=false
    local icon_sizes=(512x512 256x256 128x128 64x64 48x48)

    for size in "${icon_sizes[@]}"; do
        local icon_path="squashfs-root/usr/share/icons/hicolor/${size}/apps/emacs-appimage.png"
        if [[ -f "$icon_path" ]]; then
            print_info "Found icon: ${size}"

            # Create target directory
            local target_dir="${ICONS_DIR}/${size}/apps"
            mkdir -p "$target_dir"

            # Copy icon
            cp "$icon_path" "${target_dir}/${ICON_NAME}.png"
            print_success "Installed icon: ${target_dir}/${ICON_NAME}.png"
            icon_found=true
        fi
    done

    # Fallback: look for any emacs icon
    if [[ "$icon_found" == false ]]; then
        print_warning "Standard icons not found, searching for alternatives..."
        local fallback_icon
        fallback_icon=$(find squashfs-root -name "*emacs*.png" -o -name "*emacs*.svg" | head -1)

        if [[ -n "$fallback_icon" ]]; then
            mkdir -p "${ICONS_DIR}/256x256/apps"
            cp "$fallback_icon" "${ICONS_DIR}/256x256/apps/${ICON_NAME}.png"
            print_success "Installed fallback icon"
            icon_found=true
        fi
    fi

    # Cleanup
    cd - >/dev/null
    rm -rf "$temp_dir"

    if [[ "$icon_found" == true ]]; then
        # Update icon cache
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -f -t "${ICONS_DIR}" 2>/dev/null || true
        fi
        print_success "Icon extraction complete"
        return 0
    else
        print_warning "No icon found in AppImage"
        return 1
    fi
}

################################################################################
# Desktop Entry Creation
################################################################################

create_emacs_desktop() {
    print_header "Creating Emacs Desktop Entry"

    mkdir -p "${APPLICATIONS_DIR}"

    local desktop_file="${APPLICATIONS_DIR}/emacs-appimage.desktop"

    cat >"$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Emacs
GenericName=Text Editor
Comment=GNU Emacs text editor and IDE (AppImage)
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" %F
Icon=${ICON_NAME}
StartupWMClass=emacs-appimage
StartupNotify=true
Terminal=false
Categories=Development;TextEditor;Utility;
MimeType=text/plain;text/x-c;text/x-c++;text/x-java;text/x-lisp;text/x-python;text/x-latex;text/x-shellscript;text/x-makefile;text/x-markdown;text/x-org;
Keywords=text;editor;development;programming;emacs;
Actions=new-window;new-instance;

[Desktop Action new-window]
Name=New Window
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" --new-window %F

[Desktop Action new-instance]
Name=New Instance
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" --no-desktop %F
EOF

    chmod +x "$desktop_file"
    print_success "Created: $desktop_file"
}

create_emacsclient_desktop() {
    print_header "Creating Emacs Client Desktop Entry"

    mkdir -p "${APPLICATIONS_DIR}"

    local desktop_file="${APPLICATIONS_DIR}/emacsclient-appimage.desktop"

    cat >"$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Emacs Client
GenericName=Text Editor Client
Comment=Connect to Emacs daemon (AppImage)
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" emacsclient -c -a "" %F
Icon=${ICON_NAME}
StartupWMClass=emacs-appimage
StartupNotify=true
Terminal=false
Categories=Development;TextEditor;Utility;
MimeType=text/plain;text/x-c;text/x-c++;text/x-java;text/x-lisp;text/x-python;text/x-latex;text/x-shellscript;text/x-makefile;text/x-markdown;text/x-org;
Keywords=text;editor;development;programming;emacs;client;
Actions=terminal-client;create-frame;

[Desktop Action terminal-client]
Name=Terminal Client
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" emacsclient -t -a ""
Terminal=true

[Desktop Action create-frame]
Name=Create New Frame
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" emacsclient -c -n %F
EOF

    chmod +x "$desktop_file"
    print_success "Created: $desktop_file"
}

################################################################################
# GearLever Integration
################################################################################

integrate_with_gearlever() {
    if [[ "${GEARLEVER_TYPE}" == "none" ]]; then
        print_info "Skipping GearLever integration (not installed)"
        return 0
    fi

    print_header "Integrating with GearLever"

    # GearLever works by monitoring ~/.local/share/applications/
    # The desktop entries we created will be automatically detected

    print_info "GearLever will automatically detect the desktop entries"
    print_success "Integration complete"
}

################################################################################
# Update Desktop Database
################################################################################

update_desktop_database() {
    print_header "Updating Desktop Database"

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "${APPLICATIONS_DIR}" 2>/dev/null || true
        print_success "Desktop database updated"
    else
        print_warning "update-desktop-database not found (this is usually okay)"
    fi

    # Update MIME database
    if command -v update-mime-database &>/dev/null; then
        if [[ -d "${XDG_DATA_HOME}/mime" ]]; then
            update-mime-database "${XDG_DATA_HOME}/mime" 2>/dev/null || true
            print_success "MIME database updated"
        fi
    fi
}

################################################################################
# Uninstall
################################################################################

uninstall_integration() {
    print_header "Uninstalling Desktop Integration"

    # Remove desktop entries
    local files_removed=0

    if [[ -f "${APPLICATIONS_DIR}/emacs-appimage.desktop" ]]; then
        rm -f "${APPLICATIONS_DIR}/emacs-appimage.desktop"
        print_success "Removed Emacs desktop entry"
        ((files_removed++))
    fi

    if [[ -f "${APPLICATIONS_DIR}/emacsclient-appimage.desktop" ]]; then
        rm -f "${APPLICATIONS_DIR}/emacsclient-appimage.desktop"
        print_success "Removed Emacs Client desktop entry"
        ((files_removed++))
    fi

    # Remove icons
    local icons_removed=0
    for size in 16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
        local icon_path="${ICONS_DIR}/${size}/apps/${ICON_NAME}.png"
        if [[ -f "$icon_path" ]]; then
            rm -f "$icon_path"
            ((icons_removed++))
        fi
    done

    if [[ $icons_removed -gt 0 ]]; then
        print_success "Removed $icons_removed icon(s)"

        # Update icon cache
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -f -t "${ICONS_DIR}" 2>/dev/null || true
        fi
    fi

    # Update databases
    update_desktop_database

    if [[ $files_removed -eq 0 ]]; then
        print_warning "No integration found to remove"
    else
        print_success "Uninstall complete"
    fi
}

################################################################################
# Main Installation Flow
################################################################################

install_integration() {
    print_header "Emacs AppImage Desktop Integration"
    echo ""

    # Step 1: Detect GearLever
    detect_gearlever
    echo ""

    # Step 2: Validate AppImage
    validate_appimage
    echo ""

    # Step 3: Extract Icon
    extract_icon
    echo ""

    # Step 4: Create Desktop Entries
    create_emacs_desktop
    echo ""

    create_emacsclient_desktop
    echo ""

    # Step 5: GearLever Integration
    integrate_with_gearlever
    echo ""

    # Step 6: Update Databases
    update_desktop_database
    echo ""

    # Final Summary
    print_header "Installation Complete"
    echo ""
    print_success "Emacs AppImage has been integrated with your desktop"
    echo ""
    print_info "Desktop Entries Created:"
    echo "  • Emacs         - Main editor"
    echo "  • Emacs Client  - Client mode for daemon"
    echo ""
    print_info "You can now:"
    echo "  • Launch from application menu"
    echo "  • Set as default editor for text files"
    echo "  • Use 'Open With' context menu"
    echo ""

    if [[ "${GEARLEVER_TYPE}" != "none" ]]; then
        print_info "GearLever Integration:"
        echo "  • Open GearLever to manage this AppImage"
        echo "  • Desktop entries are automatically tracked"
    fi

    echo ""
    print_info "To start Emacs daemon (recommended for client mode):"
    echo "  ${APPIMAGE_PATH} --daemon"
    echo ""
    print_info "To uninstall: $0 --uninstall"
    echo ""
}

################################################################################
# Argument Parsing
################################################################################

UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
    --appimage)
        APPIMAGE_PATH="$2"
        APPIMAGE_DIR=$(dirname "$APPIMAGE_PATH")
        APPIMAGE_NAME=$(basename "$APPIMAGE_PATH")
        shift 2
        ;;
    --icon-name)
        ICON_NAME="$2"
        shift 2
        ;;
    --uninstall)
        UNINSTALL=true
        shift
        ;;
    --help | -h)
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
done

################################################################################
# Main Execution
################################################################################

if [[ "$UNINSTALL" == true ]]; then
    uninstall_integration
else
    install_integration
fi
