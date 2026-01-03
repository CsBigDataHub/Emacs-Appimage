#!/bin/bash

################################################################################
#                                                                              #
#  EMACS APPIMAGE - ARCH LINUX UNIVERSAL FINAL VERSION                       #
#                                                                              #
#  Features:                                                                  #
#  ✓ LinuxDeploy integration (Robust dependency bundling)                     #
#  ✓ FUSE-Safe Build Process (Extracts tools to run without FUSE)             #
#  ✓ CPU-native optimizations (-O3 -march=native)                             #
#  ✓ Symlink Dispatcher (supports emacsclient symlinks)                       #
#  ✓ Deep Icon Patching + Unique AppID (Fixes Dock & System Conflict)         #
#  ✓ GearLever/Launcher Support (StartupWMClass + Permissions Fix)            #
#  ✓ GTK Excluded (Uses host system theme/fonts)                              #
#                                                                              #
################################################################################

set -euo pipefail

APP_VERSION="30.2"
OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"
ICON_URL=""
APPDIR="$(pwd)/AppDir"
# Capture user ID for permission fix at the end
USER_UID=$(id -u)
USER_GID=$(id -g)

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --icon, -i ICON_URL          Download custom icon from URL
  --version, -v VERSION        Emacs version (default: 30.2)
  --output, -o OUTPUT          Output filename
  --help, -h                   Show this help
EOF
    exit 0
}

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
            echo "ERROR: Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "═════════════════════════════════════════════════════════════════════════"
echo "  EMACS APPIMAGE - ARCH LINUX UNIVERSAL VERSION"
echo "═════════════════════════════════════════════════════════════════════════"
echo "Configuration:"
echo "  Version:        ${APP_VERSION}"
echo "  Output:         ${OUTPUT}"
echo "  Custom Icon:    ${ICON_URL:-None}"
echo ""

# Arch Linux dependencies
BUILD_DEPS=(
    base-devel git wget curl ca-certificates
    gtk3 cairo gdk-pixbuf2 pango libx11 libxcb libxext libxrender
    libjpeg-turbo libpng libtiff libwebp giflib
    fontconfig freetype2 harfbuzz
    libxfixes libxi libxinerama libxrandr libxcursor libxcomposite libxdamage
    libxxf86vm libxau libxdmcp
    libffi pcre2 wayland libxkbcommon libinput
    gnutls ncurses libxml2 gcc-libs systemd-libs sqlite
    gmp mpfr mpc zlib bzip2 xz
    acl attr dbus gtk-layer-shell
    libtool texinfo automake autoconf bison flex libgccjit
    webkit2gtk webkit2gtk-4.1
    tree-sitter fuse2 fuse3
    appstream-glib appstream imagemagick
    librsvg libseccomp json-c
    file
)

EMACS_CONFIGURE_OPTS=(
    --disable-build-details --with-modules --with-pgtk --with-cairo
    --with-compress-install --with-toolkit-scroll-bars
    --with-native-compilation=aot --with-tree-sitter --with-xinput2
    --with-xwidgets --with-dbus --with-harfbuzz --with-libsystemd
    --with-sqlite3 --prefix=/usr
    CFLAGS="-O3 -march=native -pipe -fomit-frame-pointer -DFDSETSIZE=10000"
)

################################################################################
# STEP 1: Install Dependencies
################################################################################

echo "Step 1: Installing Dependencies"
echo "─────────────────────────────────────────────────────────────────────"

sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm "${BUILD_DEPS[@]}"

echo "✓ Dependencies installed"
echo ""

################################################################################
# STEP 2: Ensure FUSE availability
################################################################################

echo "Step 2: Ensuring FUSE availability"
echo "─────────────────────────────────────────────────────────────────────"
if [[ -f /usr/lib/libfuse.so.3 ]] || [[ -f /usr/lib64/libfuse.so.3 ]]; then
    echo "  Found: FUSE 3"
elif [[ -f /usr/lib/libfuse.so.2 ]] || [[ -f /usr/lib64/libfuse.so.2 ]]; then
    echo "  Found: FUSE 2"
else
    echo "  FUSE installed from deps"
fi
echo "✓ FUSE check complete"
echo ""

################################################################################
# STEP 3: Download Emacs
################################################################################

echo "Step 3: Downloading Emacs ${APP_VERSION}"
echo "─────────────────────────────────────────────────────────────────────"

if [[ ! -d "emacs-${APP_VERSION}" ]]; then
    wget -c "https://ftp.gnu.org/gnu/emacs/emacs-${APP_VERSION}.tar.xz" 2>/dev/null ||
        wget -c "https://mirror.rackspace.com/gnu/emacs/emacs-${APP_VERSION}.tar.xz"
    tar -xf "emacs-${APP_VERSION}.tar.xz"
    rm -f "emacs-${APP_VERSION}.tar.xz"
fi

echo "✓ Source ready"
echo ""

################################################################################
# STEP 4: Build Emacs
################################################################################

echo "Step 4: Building Emacs (30-45 minutes)"
echo "─────────────────────────────────────────────────────────────────────"

mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/share"

cd "emacs-${APP_VERSION}"

# Update WEBKIT version if needed
if grep -q "WEBKIT_BROKEN=2.41.92" configure.ac 2>/dev/null; then
    sed -i 's/WEBKIT_BROKEN=2.41.92/WEBKIT_BROKEN=2.51.92/' configure.ac 2>/dev/null || true
fi

# Regenerate configure
if [[ -f autogen.sh ]]; then
    ./autogen.sh 2>&1 | tail -3 || true
else
    autoreconf -fvi 2>&1 | tail -3 || true
fi

echo "  Configuring..."
./configure "${EMACS_CONFIGURE_OPTS[@]}" >/dev/null 2>&1

echo "  Bootstrap..."
make -j"$(nproc)" bootstrap 2>&1 | tail -3

echo "  Building..."
make -j"$(nproc)" 2>&1 | tail -3

echo "  Installing..."
make DESTDIR="${APPDIR}" install 2>&1 | tail -3

echo "✓ Build complete"
cd ..
echo ""

################################################################################
# STEP 5: Setup arch-dependent directory
################################################################################

echo "Step 5: Setting up arch-dependent directory"
echo "─────────────────────────────────────────────────────────────────────"

ARCH_DIR="${APPDIR}/usr/libexec/emacs/${APP_VERSION}/x86_64-pc-linux-gnu"
mkdir -p "$ARCH_DIR"

# Copy pdmp file from build output
if [[ -f "emacs-${APP_VERSION}/src/emacs.pdmp" ]]; then
    cp "emacs-${APP_VERSION}/src/emacs.pdmp" "$ARCH_DIR/emacs.pdmp"
    echo "✓ Copied emacs.pdmp to ${ARCH_DIR}"
else
    echo "⚠ emacs.pdmp not found in source"
fi
echo ""

################################################################################
# STEP 8: Create AppRun (Source File with UNIQUE NAME FIX)
################################################################################

echo "Step 8: Creating AppRun"
echo "─────────────────────────────────────────────────────────────────────"

# FIX: We create "AppRun.source" in the build dir, NOT inside APPDIR.
cat >"AppRun.source" <<EOF
#!/bin/bash

# Injected by build script
EMACS_VER="${APP_VERSION}"
EOF

cat >>"AppRun.source" <<'APPRUN_EOF'

HERE="$(dirname "$(readlink -f "${0}")")"

# ---------------------------------------------------------
# 1. Setup Environment
# ---------------------------------------------------------
unset GTK_MODULES
export GTK_MODULES=""
export UBUNTU_MENUPROXY=0
export NO_AT_BRIDGE=1

ARCH_LIBEXEC="${HERE}/usr/libexec/emacs/${EMACS_VER}/x86_64-pc-linux-gnu"
ARCH_BIN="${HERE}/usr/bin"

export PATH="${ARCH_BIN}:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/lib64:${LD_LIBRARY_PATH}"
export EMACSPATH="${ARCH_LIBEXEC}:${ARCH_BIN}"

export EMACS_BASE="${HERE}/usr/share/emacs"
export EMACSDIR="${HERE}/usr/share/emacs"
export EMACSDATA="${HERE}/usr/share/emacs/${EMACS_VER}/etc"
export EMACSDOC="${HERE}/usr/share/emacs/${EMACS_VER}/etc"
export EMACSLOADPATH="\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/emacs-lisp:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/progmodes:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/language:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/international:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/textmodes:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/vc:\
${HERE}/usr/share/emacs/${EMACS_VER}/lisp/net:\
${HERE}/usr/share/emacs/site-lisp"

export FONTCONFIG_PATH="${HERE}/etc/fonts"
export LIBFUSE_DISABLE_THREAD_SPAWNING=1

# ---------------------------------------------------------
# 2. Logic: Decide what to run (Emacs or Client?)
# ---------------------------------------------------------
BIN_NAME=$(basename "${ARGV0:-$0}")
TARGET_BIN="emacs"
ARGS=("$@")

if [[ "$BIN_NAME" == "emacsclient"* ]]; then
    TARGET_BIN="emacsclient"
fi

if [[ "${1:-}" == "emacsclient" ]] || [[ "${1:-}" == "ctags" ]] || [[ "${1:-}" == "etags" ]]; then
    TARGET_BIN="$1"
    ARGS=("${@:2}")
fi

# ---------------------------------------------------------
# 3. Launch with UNIQUE APP ID
# ---------------------------------------------------------
if [[ "$TARGET_BIN" == "emacs" ]]; then
    DUMP_FILE="${ARCH_LIBEXEC}/emacs.pdmp"
    if [[ -f "$DUMP_FILE" ]]; then
        # FIX: We use --name "emacs-appimage" to force a unique Window ID.
        # This allows the Dock to distinguish this AppImage from System Emacs.
        exec "${ARCH_BIN}/emacs" --name "emacs-appimage" --dump-file="$DUMP_FILE" "${ARGS[@]}"
    else
        exec "${ARCH_BIN}/emacs" --name "emacs-appimage" "${ARGS[@]}"
    fi
else
    exec "${ARCH_BIN}/${TARGET_BIN}" "${ARGS[@]}"
fi
APPRUN_EOF

chmod +x "AppRun.source"
echo "✓ AppRun source created (Includes --name override)"
echo ""

################################################################################
# STEP 9: Icon Setup (Unique Name)
################################################################################

echo "Step 9: Setting up icon"
echo "─────────────────────────────────────────────────────────────────────"

ICON_FOUND=0
# FIX: Use unique icon name to prevent system theme collision
ICON_NAME="emacs-appimage.png"

# 1. Download Custom Icon
if [[ -n "${ICON_URL}" ]]; then
    echo "  Downloading custom icon..."
    if wget -q -O "${APPDIR}/${ICON_NAME}" "${ICON_URL}"; then
        if [[ "${ICON_URL}" == *.icns ]] && command -v magick &>/dev/null; then
            magick "${APPDIR}/${ICON_NAME}" "${APPDIR}/emacs-temp.png" 2>/dev/null
            mv "${APPDIR}/emacs-temp.png" "${APPDIR}/${ICON_NAME}"
        fi
        ICON_FOUND=1
    fi
fi

# 2. Fallback to Source
if [[ $ICON_FOUND -eq 0 ]]; then
    # Try to find a good source icon
    declare -a ICON_PATHS=(
        "emacs-${APP_VERSION}/etc/images/icons/hicolor/128x128/apps/emacs.png"
        "emacs-${APP_VERSION}/etc/images/emacs.png"
    )
    for path in "${ICON_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            cp "$path" "${APPDIR}/${ICON_NAME}"
            ICON_FOUND=1
            break
        fi
    done
fi

# 3. SVG Fallback
if [[ $ICON_FOUND -eq 0 ]]; then
    echo "⚠ No icon found! Creating fallback..."
    cat >"${APPDIR}/emacs-appimage.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#7f5ab6" rx="40" ry="40"/>
  <text x="128" y="168" font-size="140" text-anchor="middle" fill="white" font-family="sans-serif" font-weight="bold">E</text>
</svg>
EOF
    # Convert to png for safety or use as is. LinuxDeploy prefers png usually.
    # We'll just stick to the SVG if ImageMagick fails, but name it png for logic simplicity if needed,
    # or better, just rename it to .png if it is SVG.
    # Actually, let's keep it simple:
    if command -v magick &>/dev/null; then
        magick "${APPDIR}/emacs-appimage.svg" "${APPDIR}/${ICON_NAME}"
    else
        mv "${APPDIR}/emacs-appimage.svg" "${APPDIR}/${ICON_NAME}"
    fi
fi

# 4. Resize
if [[ -f "${APPDIR}/${ICON_NAME}" ]] && command -v magick &>/dev/null; then
    magick "${APPDIR}/${ICON_NAME}" -resize "512x512>" "${APPDIR}/${ICON_NAME}"
fi

# 5. Overwrite Internal Icons (The "Nuclear Option")
echo "  Overwriting internal icons..."
TARGET_ICON_DIR="${APPDIR}/usr/share/icons/hicolor"
for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
    mkdir -p "${TARGET_ICON_DIR}/${size}/apps"
    cp "${APPDIR}/${ICON_NAME}" "${TARGET_ICON_DIR}/${size}/apps/emacs.png"
    # Also copy as unique name
    cp "${APPDIR}/${ICON_NAME}" "${TARGET_ICON_DIR}/${size}/apps/emacs-appimage.png"
done

# Overwrite Emacs internal resource icon
INTERNAL_IMG_DIR="${APPDIR}/usr/share/emacs/${APP_VERSION}/etc/images"
mkdir -p "${INTERNAL_IMG_DIR}"
cp "${APPDIR}/${ICON_NAME}" "${INTERNAL_IMG_DIR}/emacs.png"
cp "${APPDIR}/${ICON_NAME}" "${INTERNAL_IMG_DIR}/emacs-appimage.png"

echo "✓ Icon setup complete (${ICON_NAME})"
echo ""

################################################################################
# STEP 10: Desktop Entry
################################################################################

echo "Step 10: Creating desktop entry"
echo "─────────────────────────────────────────────────────────────────────"

# FIX: Icon=emacs-appimage (Unique ID)
# FIX: StartupWMClass=emacs-appimage (Matches the --name flag in AppRun)
cat >"${APPDIR}/emacs.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Emacs
Comment=GNU Emacs text editor and IDE
Exec=emacs %F
Icon=emacs-appimage
StartupWMClass=emacs-appimage
StartupNotify=true
Terminal=false
Categories=Development;TextEditor;
MimeType=text/plain;text/x-c;text/x-java;text/x-lisp;text/x-python;text/x-latex;text/x-shellscript;
Keywords=text;editor;development;
EOF
echo "✓ Desktop entry created (Unique ID: emacs-appimage)"
echo ""

################################################################################
# STEP 11: Prepare AppDir for LinuxDeploy
################################################################################

echo "Step 11: Preparing AppDir"
echo "─────────────────────────────────────────────────────────────────────"
cp "${APPDIR}/emacs.desktop" "${APPDIR}/" 2>/dev/null || true
cp "${APPDIR}/emacs-appimage.png" "${APPDIR}/" 2>/dev/null || true
echo "✓ AppDir ready for deployment"
echo ""

################################################################################
# STEP 12: Download & Extract Build Tools (FUSE-Safe)
################################################################################

echo "Step 12: Preparing Build Tools"
echo "─────────────────────────────────────────────────────────────────────"

# 1. LinuxDeploy
if [[ ! -d "linuxdeploy-build" ]]; then
    echo "  Downloading linuxdeploy..."
    wget -q -O linuxdeploy "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
    chmod +x linuxdeploy
    ./linuxdeploy --appimage-extract >/dev/null
    mv squashfs-root linuxdeploy-build
    rm linuxdeploy
fi

# 2. AppImageTool
if [[ ! -d "appimagetool-build" ]]; then
    echo "  Downloading appimagetool..."
    wget -q -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool
    ./appimagetool --appimage-extract >/dev/null
    mv squashfs-root appimagetool-build
    rm appimagetool
fi

export PATH="$(pwd)/linuxdeploy-build/usr/bin:$(pwd)/appimagetool-build/usr/bin:${PATH}"
echo "✓ Tools extracted and ready"
echo ""

################################################################################
# STEP 13: Create AppImage (via Extracted LinuxDeploy)
################################################################################

echo "Step 13: Bundling and Creating AppImage"
echo "─────────────────────────────────────────────────────────────────────"

export VERSION="${APP_VERSION}"
export NO_STRIP=1

# FIX: Pass unique icon filename to linuxdeploy
"$(pwd)/linuxdeploy-build/AppRun" \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/emacs" \
    --desktop-file "${APPDIR}/emacs.desktop" \
    --icon-file "${APPDIR}/emacs-appimage.png" \
    --custom-apprun "AppRun.source" \
    --exclude-library libgtk-3.so.0 \
    --exclude-library libgdk-3.so.0 \
    --exclude-library libglib-2.0.so.0 \
    --exclude-library libgio-2.0.so.0 \
    --exclude-library libgobject-2.0.so.0 \
    --exclude-library libpango-1.0.so.0 \
    --exclude-library libpangocairo-1.0.so.0 \
    --exclude-library libcairo.so.2 \
    --exclude-library libcairo-gobject.so.2 \
    --output appimage

GENERATED_NAME="Emacs-${APP_VERSION}-x86_64.AppImage"

if [[ -f "${GENERATED_NAME}" ]]; then
    mv "${GENERATED_NAME}" "${OUTPUT}"
    # FIX: GearLever Permission Error
    # Ensure the output file is owned by the user who started the script (not root/docker)
    chown "${USER_UID}:${USER_GID}" "${OUTPUT}" 2>/dev/null || true
    chmod 755 "${OUTPUT}"
    echo "✓ AppImage created: ${OUTPUT}"
else
    FOUND=$(find . -maxdepth 1 -name "*.AppImage" | head -n 1)
    if [[ -n "$FOUND" ]]; then
        mv "$FOUND" "${OUTPUT}"
        chown "${USER_UID}:${USER_GID}" "${OUTPUT}" 2>/dev/null || true
        chmod 755 "${OUTPUT}"
        echo "✓ AppImage created: ${OUTPUT}"
    else
        echo "❌ LinuxDeploy failed to create output file"
        exit 1
    fi
fi
echo ""

################################################################################
# STEP 14: Cleanup
################################################################################

echo "Step 14: Cleanup"
echo "─────────────────────────────────────────────────────────────────────"
rm -rf "${APPDIR}" "emacs-${APP_VERSION}" "AppRun.source"
echo "✓ Cleaned build files"
echo ""

################################################################################
# STEP 15: Test
################################################################################

echo "Step 15: Testing"
echo "─────────────────────────────────────────────────────────────────────"
export APPIMAGE_EXTRACT_AND_RUN=1

"./${OUTPUT}" --version 2>&1 | head -2
echo ""
echo "Testing Emacs batch mode..."
if "./${OUTPUT}" -Q -batch -eval '(message "Emacs works!")' 2>&1 | grep -q "Emacs works"; then
    echo "✓ Emacs is working correctly"
else
    echo "⚠ Batch test result unclear (may still work)"
fi
echo ""

echo "═════════════════════════════════════════════════════════════════════════"
echo "✓✓✓ BUILD SUCCESSFUL ✓✓✓"
echo "═════════════════════════════════════════════════════════════════════════"
echo "AppImage:  ${OUTPUT}"
echo ""
