#!/bin/bash

# Emacs AppImage Build Script for Linux
# Based on macOS builds with xwidgets support
# Creates a portable, self-contained Emacs AppImage

set -euo pipefail

# Display help message
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --icon, -i ICON_URL      Use custom icon URL (e.g., https://example.com/icon.png)
  --version, -v VERSION    Emacs version to build (default: 29.4)
  --output, -o OUTPUT      Output filename (default: emacs-{version}-x86_64.AppImage)
  --help, -h               Show this help message

Examples:
  $0 --icon https://github.com/emacsfodder/Infinite-Yak-Icons/raw/refs/heads/main/icns/GoldenYak.icns
  $0 --version 29.4 --output my-emacs.AppImage
  $0 --icon https://example.com/icon.png --version 29.4
EOF
    exit 0
}

# Parse command line arguments
ICON_URL=""
APP_VERSION="29.4"
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

# Configuration
APP_NAME="Emacs"
APP_VERSION="${APP_VERSION:-30.2}" # Update as needed
APP_DIR="AppDir"
APPDIR="${APP_DIR}"
OUTPUT="${OUTPUT:-emacs-${APP_VERSION}-x86_64.AppImage}"

# Emacs configuration options (preserving your macOS options, adapted for Linux)
# Note: --with-xwidgets requires GTK3 support
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
    --prefix="${APPDIR}/usr"
    "CFLAGS=-O2 -pipe -fomit-frame-pointer -DFD_SETSIZE=10000"
)

# System dependencies required for building
BUILD_DEPS=(
    base-devel
    git
    wget
    curl
    ca-certificates
    gtk3
    gnutls
    ncurses
    libxml2
    libjpeg-turbo
    libpng
    libtiff
    libwebp
    gcc-libs
    systemd-libs
    sqlite
    harfbuzz
    libx11
    libxcb
    libxext
    libxrender
    libxfixes
    libxi
    libxinerama
    libxrandr
    libxcursor
    libxcomposite
    libxdamage
    libxxf86vm
    libxau
    libxdmcp
    pcre2
    libffi
    wayland
    libxkbcommon
    librsvg
    gmp
    mpfr
    mpc
    acl
    attr
    libselinux
    dbus
    gtk-layer-shell
    libtool
    texinfo
    automake
    autoconf
    bison
    flex
    libgccjit
    webkit2gtk
)

# AppImage tools
APPIMAGE_TOOLS=(
    linuxdeploy
    appimagetool
)

# Function to install system dependencies
install_dependencies() {
    echo "Installing system dependencies..."

    # Detect package manager
    if command -v apt-get &>/dev/null; then
        echo "Using apt-get package manager..."
        sudo apt-get update || {
            echo "Failed to update apt packages"
            exit 1
        }
        sudo apt-get install -y "${BUILD_DEPS[@]}" || {
            echo "Failed to install dependencies"
            exit 1
        }
    elif command -v dnf &>/dev/null; then
        echo "Using dnf package manager..."
        sudo dnf install -y "${BUILD_DEPS[@]}" || {
            echo "Failed to install dependencies"
            exit 1
        }
    elif command -v yum &>/dev/null; then
        echo "Using yum package manager..."
        sudo yum install -y "${BUILD_DEPS[@]}" || {
            echo "Failed to install dependencies"
            exit 1
        }
    elif command -v pacman &>/dev/null; then
        echo "Using pacman package manager..."
        sudo pacman -Syu --noconfirm "${BUILD_DEPS[@]}" || {
            echo "Failed to install dependencies"
            exit 1
        }
    else
        echo "Unsupported package manager. Please install dependencies manually."
        echo "Required dependencies: ${BUILD_DEPS[*]}"
        exit 1
    fi
}

# Function to install AppImage tools
install_appimage_tools() {
    echo "Installing AppImage tools..."

    # Install linuxdeploy
    if [[ ! -f linuxdeploy ]]; then
        echo "Downloading linuxdeploy..."
        if ! wget -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"; then
            echo "Failed to download linuxdeploy"
            exit 1
        fi
        chmod +x linuxdeploy-x86_64.AppImage || {
            echo "Failed to make linuxdeploy executable"
            exit 1
        }
        mv linuxdeploy-x86_64.AppImage linuxdeploy || {
            echo "Failed to rename linuxdeploy"
            exit 1
        }
    fi

    # Install appimagetool
    if [[ ! -f appimagetool ]]; then
        echo "Downloading appimagetool..."
        if ! wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"; then
            echo "Failed to download appimagetool"
            exit 1
        fi
        chmod +x appimagetool-x86_64.AppImage || {
            echo "Failed to make appimagetool executable"
            exit 1
        }
        mv appimagetool-x86_64.AppImage appimagetool || {
            echo "Failed to rename appimagetool"
            exit 1
        }
    fi
}

# Function to download Emacs source
download_emacs() {
    echo "Downloading Emacs source..."

    # Download Emacs source from GNU mirrors
    if [[ ! -d emacs-${APP_VERSION} ]]; then
        if ! wget -c "https://ftp.gnu.org/gnu/emacs/emacs-${APP_VERSION}.tar.xz"; then
            echo "Failed to download Emacs source"
            exit 1
        fi
        if ! tar -xf "emacs-${APP_VERSION}.tar.xz"; then
            echo "Failed to extract Emacs source"
            exit 1
        fi
        rm -f "emacs-${APP_VERSION}.tar.xz" || echo "Warning: Failed to remove tar.xz file"
    fi
}

# Function to configure and build Emacs
build_emacs() {
    echo "Configuring and building Emacs..."

    cd "emacs-${APP_VERSION}" || {
        echo "Failed to enter Emacs source directory"
        exit 1
    }

    # Configure Emacs
    if ! ./configure "${EMACS_CONFIGURE_OPTS[@]}"; then
        echo "Failed to configure Emacs"
        exit 1
    fi

    # Build Emacs
    echo "Building Emacs (this may take a while)..."
    if ! make -j"$(nproc)" bootstrap; then
        echo "Failed to bootstrap Emacs"
        exit 1
    fi

    if ! make -j"$(nproc)"; then
        echo "Failed to build Emacs"
        exit 1
    fi

    # Install to AppDir
    if ! make install; then
        echo "Failed to install Emacs"
        exit 1
    fi

    # Remove emacsclient to disable client-server functionality
    rm -f "${APPDIR}/usr/bin/emacsclient" || echo "Warning: Failed to remove emacsclient"

    cd .. || {
        echo "Failed to return to parent directory"
        exit 1
    }
}

# Function to create AppRun script
create_apprun() {
    echo "Creating AppRun script..."

    cat >"${APPDIR}/AppRun" <<'EOF'
#!/bin/bash

# Debug logging
LOG_FILE="$HOME/emacs-appimage-run.log"
exec > >(tee -a "$LOG_FILE") 2>&1

export PATH="${APPDIR}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${LD_LIBRARY_PATH}"
export EMACSDATA="${APPDIR}/usr/share/emacs"
export EMACSLOADPATH="${APPDIR}/usr/share/emacs/site-lisp"

# Run Emacs
exec "${APPDIR}/usr/bin/emacs" "$@"
EOF

    chmod +x "${APPDIR}/AppRun"
}

# Function to bundle libraries
bundle_libraries() {
    echo "Bundling libraries..."

    # Copy essential libraries
    mkdir -p "${APPDIR}/usr/lib"

    # Copy Emacs libraries
    if [[ -d "emacs-${APP_VERSION}/lib" ]]; then
        cp -r "emacs-${APP_VERSION}/lib" "${APPDIR}/usr/" || true
    fi

    # Define libraries to bundle
    declare -a LIBRARIES=(
        "libgtk-3*"
        "libgdk-3*"
        "libglib-2.0*"
        "libgobject-2.0*"
        "libgio-2.0*"
        "libgthread-2.0*"
        "libpango*"
        "libcairo*"
        "libfontconfig*"
        "libfreetype*"
        "libharfbuzz*"
        "libpng*"
        "libjpeg*"
        "libtiff*"
        "libwebp*"
        "librsvg*"
        "libgcc_s.so*"
        "libstdc++*"
        "libm.so*"
        "libc.so*"
        "libdl.so*"
        "libpthread.so*"
        "librt.so*"
        "libresolv.so*"
        "libz.so*"
        "libbz2.so*"
        "liblzma.so*"
        "libselinux.so*"
        "libacl.so*"
        "libattr.so*"
        "libdbus*"
        "libsystemd*"
        "libsqlite3*"
        "libgmp*"
        "libmpfr*"
        "libmpc*"
        "libgccjit*"
        "libxcb*"
        "libX11*"
        "libXext*"
        "libXrender*"
        "libXfixes*"
        "libXi*"
        "libXtst*"
        "libXinerama*"
        "libXrandr*"
        "libXcursor*"
        "libXcomposite*"
        "libXdamage*"
        "libXxf86vm*"
        "libXau*"
        "libXdmcp*"
        "libxkbcommon*"
        "libwayland*"
        "libffi*"
        "libpcre*"
        "libiconv*"
        "libintl*"
        "libxml2*"
        "liblz4*"
        "libsnappy*"
        "libzstd*"
    )

    # Copy system libraries if needed
    if [[ -d /usr/lib ]]; then
        for lib in "${LIBRARIES[@]}"; do
            cp /usr/lib/"${lib}" "${APPDIR}/usr/lib/" 2>/dev/null || true
        done
    fi
}

# Function to download custom icon
download_icon() {
    if [[ -n "${ICON_URL}" ]]; then
        echo "Downloading custom icon from ${ICON_URL}..."

        # Extract filename from URL
        ICON_FILENAME=$(basename "${ICON_URL}")

        # Download icon
        if ! wget -q "${ICON_URL}" -O "${APPDIR}/${ICON_FILENAME}"; then
            echo "Failed to download icon from ${ICON_URL}"
            return 1
        fi

        # Convert icon to PNG format if needed
        if [[ "${ICON_FILENAME}" == *.icns ]]; then
            echo "Converting .icns to .png..."
            # Use ImageMagick to convert (install with: sudo apt-get install imagemagick)
            if command -v convert &>/dev/null; then
                convert "${APPDIR}/${ICON_FILENAME}" "${APPDIR}/emacs.png"
                ICON_FILENAME="emacs.png"
            else
                echo "Warning: ImageMagick not found, using original .icns file"
            fi
        fi

        # Set icon name for desktop entry
        ICON_NAME="${ICON_FILENAME%.*}"
    else
        # Use default icon
        ICON_NAME="emacs"
    fi
}

# Function to create desktop entry
create_desktop_entry() {
    echo "Creating desktop entry..."

    cat >"${APPDIR}/emacs.desktop" <<EOF
[Desktop Entry]
Name=Emacs
Exec=AppRun
Icon=${ICON_NAME}
Type=Application
Categories=Utility;TextEditor;
Terminal=false
StartupWMClass=Emacs
EOF
}

# Function to create AppImage
create_appimage() {
    echo "Creating AppImage..."

    # Use linuxdeploy to bundle the AppImage
    if ! ./linuxdeploy --appdir "${APPDIR}" --output appimage; then
        echo "Failed to create AppImage with linuxdeploy"
        exit 1
    fi

    # Rename the output file
    APPIMAGE_OUTPUT=$(ls *.AppImage 2>/dev/null | head -1)
    if [[ -z "${APPIMAGE_OUTPUT}" ]]; then
        echo "No AppImage file found after linuxdeploy"
        exit 1
    fi

    if ! mv "${APPIMAGE_OUTPUT}" "${OUTPUT}"; then
        echo "Failed to rename AppImage file"
        exit 1
    fi
}

# Main build function
main() {
    echo "Starting Emacs AppImage build..."
    echo "Configuration:"
    echo "  Version: ${APP_VERSION}"
    echo "  Output: ${OUTPUT}"
    if [[ -n "${ICON_URL}" ]]; then
        echo "  Custom Icon: ${ICON_URL}"
    else
        echo "  Custom Icon: None (using default)"
    fi

    # Clean up previous builds
    rm -rf "${APP_DIR}" emacs-${APP_VERSION} emacs-${APP_VERSION}.tar.xz

    # Install dependencies
    install_dependencies

    # Install AppImage tools
    install_appimage_tools

    # Download Emacs source
    download_emacs

    # Configure and build Emacs
    build_emacs

    # Create AppRun script
    create_apprun

    # Download custom icon if specified
    if ! download_icon; then
        echo "Warning: Icon download failed, continuing with default icon"
    fi

    # Bundle libraries
    bundle_libraries

    # Create desktop entry
    create_desktop_entry

    # Create AppImage
    create_appimage

    echo "Build completed successfully!"
    echo "AppImage created: ${OUTPUT}"
}

# Run main function
main "$@"
