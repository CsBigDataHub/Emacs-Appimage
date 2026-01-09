#!/bin/bash

################################################################################
#                                                                              #
#  EMACS APPIMAGE - GEARLEVER DESKTOP INTEGRATION                              #
#                                                                              #
#  Creates two desktop entries:                                                #
#  1. Emacs - Main editor                                                      #
#  2. EmacsClient - Client mode for existing daemon                            #
#                                                                              #
#  Supports both Flatpak and standalone GearLever installations                #
#                                                                              #
################################################################################

set -euo pipefail

# Configuration
# Using ${HOME} ensures it works for 'mypc' or any other user
APPIMAGE_ROOT="${HOME}/AppImages"
APPIMAGE_NAME="emacs-30.2-x86_64.AppImage"
# Initial path (where it is now) vs Target path (where it should be)
INITIAL_APPIMAGE_PATH="${2:-$PWD/$APPIMAGE_NAME}"
TARGET_APPIMAGE_PATH="${APPIMAGE_ROOT}/${APPIMAGE_NAME}"
ICON_NAME="emacs-appimage"

# Custom Icon Location requested by user
CUSTOM_ICONS_DIR="${APPIMAGE_ROOT}/.icons"
FINAL_ICON_PATH="${CUSTOM_ICONS_DIR}/${ICON_NAME}.png"

# Standard Desktop entry locations
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
APPLICATIONS_DIR="${XDG_DATA_HOME}/applications"

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
  --appimage PATH          Path to source Emacs AppImage (default: looks in current dir)
  --icon-name NAME         Icon name to use (default: ${ICON_NAME})
  --uninstall              Remove desktop integration
  --help, -h               Show this help

Environment Variables:
  APPIMAGE_ROOT            Target Directory (default: ~/AppImages)
  XDG_DATA_HOME            User data directory (default: ~/.local/share)

EOF
    exit 0
}

################################################################################
# Directory Setup & File Moving
################################################################################

prepare_directories() {
    if [[ ! -d "$APPIMAGE_ROOT" ]]; then
        print_info "Creating AppImage directory: $APPIMAGE_ROOT"
        mkdir -p "$APPIMAGE_ROOT"
    fi

    if [[ ! -d "$CUSTOM_ICONS_DIR" ]]; then
        print_info "Creating Icons directory: $CUSTOM_ICONS_DIR"
        mkdir -p "$CUSTOM_ICONS_DIR"
    fi
}

move_and_validate_appimage() {
    print_header "Locating and Moving AppImage"

    # If the variable passed via flag is set, use it, otherwise check target, otherwise check current dir
    local source_path=""

    # 1. Check if it's already in the destination
    if [[ -f "$TARGET_APPIMAGE_PATH" ]]; then
        print_info "AppImage found in target directory."
        APPIMAGE_PATH="$TARGET_APPIMAGE_PATH"
    # 2. Check if a path was provided via arguments (handled in main parsing, checking validity here)
    elif [[ -f "$INITIAL_APPIMAGE_PATH" ]]; then
        source_path="$INITIAL_APPIMAGE_PATH"
    # 3. Last ditch check in current folder
    elif [[ -f "./$APPIMAGE_NAME" ]]; then
        source_path="./$APPIMAGE_NAME"
    else
        print_error "Could not find AppImage."
        print_info "Expected at: $TARGET_APPIMAGE_PATH"
        print_info "Or in current directory."
        exit 1
    fi

    # Perform Move if source is found and different from target
    if [[ -n "$source_path" ]] && [[ "$source_path" != "$TARGET_APPIMAGE_PATH" ]]; then
        print_info "Moving AppImage to $APPIMAGE_ROOT..."
        mv "$source_path" "$TARGET_APPIMAGE_PATH"
        APPIMAGE_PATH="$TARGET_APPIMAGE_PATH"
        print_success "Moved to $APPIMAGE_PATH"
    fi

    # Final Permission Check
    if [[ ! -x "${APPIMAGE_PATH}" ]]; then
        chmod +x "${APPIMAGE_PATH}"
        print_success "Made executable: ${APPIMAGE_PATH}"
    fi

    # Test execution
    if ! "${APPIMAGE_PATH}" --version &>/dev/null; then
        print_error "AppImage failed to execute"
        exit 1
    fi

    print_success "AppImage validated at: ${APPIMAGE_PATH}"
}

################################################################################
# Icon Extraction
################################################################################

extract_icon() {
    print_header "Extracting Icon"

    local temp_dir
    temp_dir=$(mktemp -d)

    print_info "Extracting icon from AppImage..."

    cd "$temp_dir"
    "${APPIMAGE_PATH}" --appimage-extract >/dev/null 2>&1 || {
        print_error "Failed to extract AppImage"
        rm -rf "$temp_dir"
        return 1
    }

    # Search strategy: high res png -> standard png -> svg
    local icon_found=false
    local source_icon=""

    # Try 512, 256, 128
    for size in 512x512 256x256 128x128; do
        local check_path="squashfs-root/usr/share/icons/hicolor/${size}/apps/emacs-appimage.png"
        if [[ -f "$check_path" ]]; then
            source_icon="$check_path"
            break
        fi
    done

    # Fallback to generic find
    if [[ -z "$source_icon" ]]; then
        source_icon=$(find squashfs-root -name "emacs.png" -o -name "emacs.svg" | head -1)
    fi

    if [[ -n "$source_icon" ]]; then
        cp "$source_icon" "$FINAL_ICON_PATH"
        print_success "Icon saved to: $FINAL_ICON_PATH"
        icon_found=true
    else
        print_warning "No icon found in AppImage. Desktop entry will lack icon."
    fi

    # Cleanup
    cd - >/dev/null
    rm -rf "$temp_dir"
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
Icon=${FINAL_ICON_PATH}
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
    print_header "Creating EmacsClient Desktop Entry"
    mkdir -p "${APPLICATIONS_DIR}"
    local desktop_file="${APPLICATIONS_DIR}/emacsclient-appimage.desktop"

    # NOTE: Name set to 'EmacsClient' (no space) as requested
    cat >"$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=EmacsClient
GenericName=Text Editor Client
Comment=Connect to Emacs daemon (AppImage)
Exec=env DESKTOPINTEGRATION=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 "${APPIMAGE_PATH}" emacsclient -c -a "" %F
Icon=${FINAL_ICON_PATH}
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
# Database Updates
################################################################################

update_desktop_database() {
    print_header "Updating Desktop Database"
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "${APPLICATIONS_DIR}" 2>/dev/null || true
        print_success "Desktop database updated"
    fi
}

################################################################################
# Uninstall
################################################################################

uninstall_integration() {
    print_header "Uninstalling Desktop Integration"

    local files_removed=0

    # 1. Remove Desktop Entries
    if [[ -f "${APPLICATIONS_DIR}/emacs-appimage.desktop" ]]; then
        rm -f "${APPLICATIONS_DIR}/emacs-appimage.desktop"
        print_success "Removed Emacs desktop entry"
        ((files_removed++))
    fi

    # Fix: Ensure we target the file we created, even if display name was changed
    if [[ -f "${APPLICATIONS_DIR}/emacsclient-appimage.desktop" ]]; then
        rm -f "${APPLICATIONS_DIR}/emacsclient-appimage.desktop"
        print_success "Removed EmacsClient desktop entry"
        ((files_removed++))
    fi

    # 2. Remove Icon from custom folder
    if [[ -f "$FINAL_ICON_PATH" ]]; then
        rm -f "$FINAL_ICON_PATH"
        print_success "Removed Icon from $CUSTOM_ICONS_DIR"
        ((files_removed++))
    fi

    # 3. Clean up .icons dir if empty
    if [[ -d "$CUSTOM_ICONS_DIR" ]]; then
        if [[ -z "$(ls -A "$CUSTOM_ICONS_DIR")" ]]; then
            rmdir "$CUSTOM_ICONS_DIR"
            print_info "Removed empty icon directory"
        fi
    fi

    # Update databases
    update_desktop_database

    if [[ $files_removed -eq 0 ]]; then
        print_warning "No files found to remove"
    else
        print_success "Uninstall complete"
    fi
}

################################################################################
# Main Installation Flow
################################################################################

install_integration() {
    prepare_directories
    move_and_validate_appimage
    extract_icon
    create_emacs_desktop
    create_emacsclient_desktop
    update_desktop_database

    print_header "Installation Complete"
    print_success "AppImage moved to: $APPIMAGE_PATH"
    print_success "Icons stored in: $CUSTOM_ICONS_DIR"
    print_success "Desktop entries created"
}

################################################################################
# Argument Parsing
################################################################################

UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
    --appimage)
        INITIAL_APPIMAGE_PATH="$2"
        shift 2
        ;;
    --icon-name)
        ICON_NAME="$2"
        FINAL_ICON_PATH="${CUSTOM_ICONS_DIR}/${ICON_NAME}.png"
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
        exit 1
        ;;
    esac
done

if [[ "$UNINSTALL" == true ]]; then
    uninstall_integration
else
    install_integration
fi
