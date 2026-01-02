#!/bin/bash

# Emacs AppImage Build Script for Linux - FIXED VERSION
# Fixes the "Cannot open load file: loadup.el" error by using proper relocatable paths

set -euo pipefail

# Display help message
show_help() {
    cat <<'EOF'
Usage: $0 [OPTIONS]

Options:
  --icon, -i ICON_URL      Use custom icon URL
  --version, -v VERSION    Emacs version (default: 30.2)
  --output, -o OUTPUT      Output filename
  --help, -h               Show this help

EOF
    exit 0
}

# Parse arguments
ICON_URL=""
APP_VERSION="30.2"
OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"

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
        --help | -h) show_help ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration - CRITICAL FIX: Use /usr not absolute build path
APP_NAME="Emacs"
APPDIR="$(pwd)/AppDir"

# FIXED: Use standard /usr prefix for relocatable installation
EMACS_CONFIGURE_OPTS=(
    --disable-build-details
    --with-modules
    --with-pgtk
    --with-cairo
    --with-compress-install
    --with-toolkit-scroll-bars
    --with-native-compilation=aot
    --with-tree-sitter
    --with-xinput2
    --with-xwidgets
    --with-dbus
    --with-harfbuzz
    --with-libsystemd
    --with-sqlite3
    --prefix=/usr
    CFLAGS="-O2 -pipe -fomit-frame-pointer -DFDSETSIZE=10000"
)

# Dependencies
BUILD_DEPS=(
    base-devel git wget curl ca-certificates gtk3 gnutls ncurses libxml2
    libjpeg-turbo libpng libtiff libwebp gcc-libs systemd-libs sqlite harfbuzz
    libx11 libxcb libxext libxrender libxfixes libxi libxinerama libxrandr
    libxcursor libxcomposite libxdamage libxxf86vm libxau libxdmcp pcre2
    libffi wayland libxkbcommon librsvg gmp mpfr mpc acl attr dbus
    gtk-layer-shell libtool texinfo automake autoconf bison flex libgccjit
    webkit2gtk webkit2gtk-4.1 tree-sitter appstream-glib appstream imagemagick
)

# Install dependencies
install_dependencies() {
    echo "Installing system dependencies..."

    if command -v pacman &>/dev/null; then
        sudo pacman -Syu --noconfirm "${BUILD_DEPS[@]}"
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${BUILD_DEPS[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${BUILD_DEPS[@]}"
    else
        echo "Unsupported package manager"
        exit 1
    fi
}

# Download Emacs
download_emacs() {
    if [[ ! -d emacs-${APP_VERSION} ]]; then
        echo "Downloading Emacs ${APP_VERSION}..."
        wget -c "https://ftp.gnu.org/gnu/emacs/emacs-${APP_VERSION}.tar.xz" ||
            wget -c "https://mirror.rackspace.com/gnu/emacs/emacs-${APP_VERSION}.tar.xz"
        tar -xf "emacs-${APP_VERSION}.tar.xz"
        rm -f "emacs-${APP_VERSION}.tar.xz"
    fi
}

# Build Emacs
build_emacs() {
    echo "Building Emacs..."
    cd "emacs-${APP_VERSION}"

    # Update WEBKIT_BROKEN version
    if grep -q "WEBKIT_BROKEN=2.41.92" configure.ac; then
        sed -i 's/WEBKIT_BROKEN=2.41.92/WEBKIT_BROKEN=2.51.92/' configure.ac
    fi

    ./autogen.sh 2>/dev/null || autoreconf -fvi
    ./configure "${EMACS_CONFIGURE_OPTS[@]}"
    make -j"$(nproc)" bootstrap
    make -j"$(nproc)"

    # CRITICAL FIX: Use DESTDIR for proper staging
    echo "Installing to AppDir with DESTDIR..."
    make DESTDIR="${APPDIR}" install

    # Verify installation
    if [[ ! -f "${APPDIR}/usr/bin/emacs" ]]; then
        echo "ERROR: Emacs not installed correctly"
        exit 1
    fi

    echo "Emacs successfully installed to ${APPDIR}/usr"
    cd ..
}

# Create AppRun script
create_apprun() {
    echo "Creating AppRun script..."

    cat >"${APPDIR}/AppRun" <<'APPRUN_EOF'
#!/bin/bash

HERE="$(dirname "$(readlink -f "${0}")")"

export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/lib64:${LD_LIBRARY_PATH}"

# CRITICAL: Set Emacs paths for runtime
export EMACSDIR="${HERE}/usr/share/emacs"
export EMACSDATA="${HERE}/usr/share/emacs/30.2/etc"
export EMACSDOC="${HERE}/usr/share/emacs/30.2/etc"
export EMACSLOADPATH="${HERE}/usr/share/emacs/30.2/lisp"

exec "${HERE}/usr/bin/emacs" "$@"
APPRUN_EOF

    chmod +x "${APPDIR}/AppRun"
}

# Download icon
download_icon() {
    if [[ -d "emacs-${APP_VERSION}/etc/images/icons/hicolor/256x256/apps" ]]; then
        cp "emacs-${APP_VERSION}/etc/images/icons/hicolor/256x256/apps/emacs.png" "${APPDIR}/emacs.png"
    else
        # Create fallback icon
        touch "${APPDIR}/emacs.png"
    fi
}

# Create desktop entry
create_desktop_entry() {
    cat >"${APPDIR}/emacs.desktop" <<'EOF'
[Desktop Entry]
Name=Emacs
Comment=GNU Emacs text editor
Exec=emacs %F
Icon=emacs
Type=Application
Terminal=false
Categories=Development;TextEditor;
EOF
}

# Create AppImage
create_appimage() {
    echo "Creating AppImage structure..."

    mkdir -p "${APPDIR}/.dir"
    cp -r "${APPDIR}/usr" "${APPDIR}/.dir/"
    cp "${APPDIR}/AppRun" "${APPDIR}/.dir/"
    chmod +x "${APPDIR}/.dir/AppRun"
    cp "${APPDIR}/emacs.desktop" "${APPDIR}/.dir/"
    cp "${APPDIR}/emacs.png" "${APPDIR}/.dir/emacs.png"

    mkdir -p "${APPDIR}/.dir/usr/share/icons/hicolor/256x256/apps/"
    cp "${APPDIR}/emacs.png" "${APPDIR}/.dir/usr/share/icons/hicolor/256x256/apps/emacs.png"

    # Download appimagetool if needed
    if [[ ! -f appimagetool ]]; then
        wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x appimagetool-x86_64.AppImage
        mv appimagetool-x86_64.AppImage appimagetool
    fi

    # Create AppImage
    ./appimagetool --appimage-extract-and-run "${APPDIR}/.dir" "${OUTPUT}"
    chmod +x "${OUTPUT}"

    echo "AppImage created: ${OUTPUT}"
    ls -lh "${OUTPUT}"
}

# Cleanup
cleanup() {
    echo "Cleaning up..."
    rm -rf "${APPDIR}" "emacs-${APP_VERSION}"
}

# Main
main() {
    echo "Starting Emacs AppImage build..."

    mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/share"

    if install_dependencies &&
            download_emacs &&
            build_emacs &&
            create_apprun &&
            download_icon &&
            create_desktop_entry &&
            create_appimage; then
        echo "Build successful!"
        cleanup
    else
        echo "Build failed!"
        cleanup
        exit 1
    fi
}

main "$@"
