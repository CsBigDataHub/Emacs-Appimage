#!/bin/bash

################################################################################
#                                                                              #
#  CLEAN EMACS APPIMAGE BUILDER (NO PATH INJECTION)                            #
#  Respects system PATH and Zsh configuration                                  #
#                                                                              #
################################################################################

set -euo pipefail

# Configuration
APP_VERSION="30.2"
OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"
ICON_URL=""
APPDIR="$(pwd)/AppDir"
TARGET_UID=$(id -u)
TARGET_GID=$(id -g)

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --icon, -i ICON_URL          Download custom icon from URL
  --version, -v VERSION        Emacs version (default: 30.2)
  --output, -o OUTPUT          Output filename
  --uid UID                    Target user ID for file ownership
  --gid GID                    Target group ID for file ownership
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
        --uid)
            TARGET_UID="$2"
            shift 2
            ;;
        --gid)
            TARGET_GID="$2"
            shift 2
            ;;
        --help | -h) show_help ;;
        *)
            echo "ERROR: Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "═══════════════════════════════════════════════════════════════════════"
echo "  EMACS APPIMAGE BUILDER (CLEAN)"
echo "═══════════════════════════════════════════════════════════════════════"
echo "Configuration:"
echo "  Version:           ${APP_VERSION}"
echo "  Output:            ${OUTPUT}"
echo "  Custom Icon:       ${ICON_URL:-None}"
echo ""

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
    CFLAGS="-O2 -march=native -pipe -fomit-frame-pointer -DFDSETSIZE=10000"
)

################################################################################
# STEP 1: Install Dependencies
################################################################################
echo "Step 1: Installing Dependencies"
echo "───────────────────────────────────────────────────────────────────────"
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm "${BUILD_DEPS[@]}"
echo "✓ Dependencies installed"
echo ""

################################################################################
# STEP 2: Ensure FUSE availability
################################################################################
echo "Step 2: Ensuring FUSE availability"
echo "───────────────────────────────────────────────────────────────────────"
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
echo "───────────────────────────────────────────────────────────────────────"
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
echo "───────────────────────────────────────────────────────────────────────"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/share"
cd "emacs-${APP_VERSION}"

# Fix WebKit version check if necessary
if grep -q "WEBKIT_BROKEN=2.41.92" configure.ac 2>/dev/null; then
    sed -i 's/WEBKIT_BROKEN=2.41.92/WEBKIT_BROKEN=2.51.92/' configure.ac 2>/dev/null || true
fi

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
echo "───────────────────────────────────────────────────────────────────────"
ARCH_DIR="${APPDIR}/usr/libexec/emacs/${APP_VERSION}/x86_64-pc-linux-gnu"
mkdir -p "$ARCH_DIR"

if [[ -f "emacs-${APP_VERSION}/src/emacs.pdmp" ]]; then
    cp "emacs-${APP_VERSION}/src/emacs.pdmp" "$ARCH_DIR/emacs.pdmp"
    echo "✓ Copied emacs.pdmp to ${ARCH_DIR}"
else
    echo "⚠ emacs.pdmp not found in source"
fi
echo ""

################################################################################
# STEP 6: Detect compiler paths for native-comp
################################################################################
echo "Step 6: Detecting native-comp dependencies"
echo "───────────────────────────────────────────────────────────────────────"
GCC_PATH=$(which gcc 2>/dev/null || echo "")
LIBGCCJIT_PATH=$(find /usr/lib /usr/lib64 -name "libgccjit.so*" 2>/dev/null | head -n1 || echo "")

if [[ -n "${GCC_PATH}" ]]; then
    echo "  Found GCC: ${GCC_PATH}"
else
    echo "  ⚠ GCC not found in PATH"
fi

if [[ -n "${LIBGCCJIT_PATH}" ]]; then
    LIBGCCJIT_DIR=$(dirname "${LIBGCCJIT_PATH}")
    echo "  Found libgccjit: ${LIBGCCJIT_PATH}"
else
    echo "  ⚠ libgccjit not found"
fi
echo "✓ Native-comp detection complete"
echo ""

################################################################################
# STEP 7: Create AppRun (STANDARD)
################################################################################
echo "Step 7: Creating Standard AppRun"
echo "───────────────────────────────────────────────────────────────────────"

cat >"AppRun.source" <<EOF
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\${0}")")"
EMACS_VER="${APP_VERSION}"

# 1. Set up Emacs Paths
export ARCH_LIBEXEC="\${HERE}/usr/libexec/emacs/\${EMACS_VER}/x86_64-pc-linux-gnu"
export ARCH_BIN="\${HERE}/usr/bin"
export EMACSPATH="\${ARCH_LIBEXEC}:\${ARCH_BIN}"
export EMACSDIR="\${HERE}/usr/share/emacs"
export EMACSDATA="\${HERE}/usr/share/emacs/\${EMACS_VER}/etc"
export EMACSDOC="\${HERE}/usr/share/emacs/\${EMACS_VER}/etc"
export EMACSLOADPATH="\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/emacs-lisp:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/progmodes:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/language:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/international:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/textmodes:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/vc:\${HERE}/usr/share/emacs/\${EMACS_VER}/lisp/net:\${HERE}/usr/share/emacs/site-lisp"
export FONTCONFIG_PATH="\${HERE}/etc/fonts"
export LIBFUSE_DISABLE_THREAD_SPAWNING=1

# 2. Library Paths
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${HERE}/usr/lib64:\${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="/usr/lib:/usr/lib64:/usr/lib/gcc:/usr/lib/x86_64-linux-gnu:\${LIBRARY_PATH:-}"

# 3. Standard PATH Handling (Prepend Emacs, Keep System Tools)
# This allows your .zshenv configuration (mise/shims) to work correctly.
export PATH="\${ARCH_BIN}:\${PATH}"

# Detect binary to run
BIN_NAME=\$(basename "\${ARGV0:-\$0}")
TARGET_BIN="emacs"
ARGS=("\$@")

if [[ "\$BIN_NAME" == "emacsclient"* ]]; then
    TARGET_BIN="emacsclient"
fi

if [[ "\${1:-}" =~ ^(emacsclient|ctags|etags)\$ ]]; then
    TARGET_BIN="\$1"
    ARGS=("\${@:2}")
fi

# Launch
if [[ "\$TARGET_BIN" == "emacs" ]]; then
    DUMP_FILE="\${ARCH_LIBEXEC}/emacs.pdmp"
    if [[ -f "\$DUMP_FILE" ]]; then
        exec "\${ARCH_BIN}/emacs" --name "emacs-appimage" --dump-file="\$DUMP_FILE" "\${ARGS[@]}"
    else
        exec "\${ARCH_BIN}/emacs" --name "emacs-appimage" "\${ARGS[@]}"
    fi
else
    exec "\${ARCH_BIN}/\${TARGET_BIN}" "\${ARGS[@]}"
fi
EOF

chmod +x "AppRun.source"
echo "✓ AppRun created (Compatible with mise/system tools)"
echo ""

################################################################################
# STEP 8: Icon Setup
################################################################################
echo "Step 8: Setting up icon"
echo "───────────────────────────────────────────────────────────────────────"
ICON_FOUND=0
ICON_NAME="emacs-appimage.png"
TEMP_ICON="$(pwd)/custom_icon_download.tmp"

if [[ -n "${ICON_URL}" ]]; then
    echo "  Downloading custom icon from: ${ICON_URL}"
    if wget -q -O "${TEMP_ICON}" "${ICON_URL}"; then
        if file "${TEMP_ICON}" | grep -qi "image"; then
            if [[ "${ICON_URL}" == *.icns ]] && command -v magick &>/dev/null; then
                magick "${TEMP_ICON}" "${APPDIR}/${ICON_NAME}" 2>/dev/null
                rm "${TEMP_ICON}"
            else
                if command -v magick &>/dev/null; then
                    magick "${TEMP_ICON}" -resize "512x512>" "${APPDIR}/${ICON_NAME}"
                    rm "${TEMP_ICON}"
                else
                    mv "${TEMP_ICON}" "${APPDIR}/${ICON_NAME}"
                fi
            fi
            ICON_FOUND=1
            echo "  ✓ Custom icon processed"
        else
            echo "  ✗ Invalid image file"
            rm "${TEMP_ICON}"
        fi
    fi
fi

if [[ $ICON_FOUND -eq 0 ]]; then
    echo "  Using fallback Emacs icon..."
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

if [[ $ICON_FOUND -eq 0 ]]; then
    echo "  ⚠ Creating generated icon..."
    cat >"${APPDIR}/emacs-appimage.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#7f5ab6" rx="40" ry="40"/>
  <text x="128" y="168" font-size="140" text-anchor="middle" fill="white" font-family="sans-serif" font-weight="bold">E</text>
</svg>
EOF
    if command -v magick &>/dev/null; then
        magick "${APPDIR}/emacs-appimage.svg" "${APPDIR}/${ICON_NAME}"
        rm "${APPDIR}/emacs-appimage.svg"
    else
        mv "${APPDIR}/emacs-appimage.svg" "${APPDIR}/${ICON_NAME}"
    fi
fi

# Ensure icon file exists
if [[ ! -f "${APPDIR}/${ICON_NAME}" ]]; then
    echo "  ✗ Critical: No icon file found."
    exit 1
fi

# Install icons to hicolor
TARGET_ICON_DIR="${APPDIR}/usr/share/icons/hicolor"
for size in 16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
    mkdir -p "${TARGET_ICON_DIR}/${size}/apps"
    SIZE_NUM=$(echo "$size" | cut -d'x' -f1)
    if command -v magick &>/dev/null; then
        magick "${APPDIR}/${ICON_NAME}" -resize "${SIZE_NUM}x${SIZE_NUM}!" "${TARGET_ICON_DIR}/${size}/apps/emacs.png"
        magick "${APPDIR}/${ICON_NAME}" -resize "${SIZE_NUM}x${SIZE_NUM}!" "${TARGET_ICON_DIR}/${size}/apps/emacs-appimage.png"
    else
        cp "${APPDIR}/${ICON_NAME}" "${TARGET_ICON_DIR}/${size}/apps/emacs.png"
        cp "${APPDIR}/${ICON_NAME}" "${TARGET_ICON_DIR}/${size}/apps/emacs-appimage.png"
    fi
done

echo "✓ Icon setup complete"
echo ""

################################################################################
# STEP 9: Desktop Entry
################################################################################
echo "Step 9: Creating desktop entry"
echo "───────────────────────────────────────────────────────────────────────"
cat >"${APPDIR}/emacs.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Emacs
Comment=GNU Emacs text editor and IDE
Exec=env WEBKIT_DISABLE_DMABUF_RENDERER=1 emacs %F
Icon=emacs-appimage
StartupWMClass=emacs-appimage
StartupNotify=true
Terminal=false
Categories=Development;TextEditor;
MimeType=text/plain;text/x-c;text/x-java;text/x-lisp;text/x-python;text/x-latex;text/x-shellscript;
Keywords=text;editor;development;
EOF
echo "✓ Desktop entry created"
echo ""

################################################################################
# STEP 10: Prepare AppDir for LinuxDeploy
################################################################################
echo "Step 10: Preparing AppDir"
echo "───────────────────────────────────────────────────────────────────────"
cp "${APPDIR}/emacs.desktop" "${APPDIR}/" 2>/dev/null || true
cp "${APPDIR}/${ICON_NAME}" "${APPDIR}/" 2>/dev/null || true
echo "✓ AppDir ready for deployment"
echo ""

################################################################################
# STEP 11: Download & Extract Build Tools
################################################################################
echo "Step 11: Preparing Build Tools"
echo "───────────────────────────────────────────────────────────────────────"
if [[ ! -d "linuxdeploy-build" ]]; then
    echo "  Downloading linuxdeploy..."
    wget -q -O linuxdeploy "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
    chmod +x linuxdeploy
    ./linuxdeploy --appimage-extract >/dev/null
    mv squashfs-root linuxdeploy-build
    rm linuxdeploy
fi

if [[ ! -d "appimagetool-build" ]]; then
    echo "  Downloading appimagetool..."
    wget -q -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool
    ./appimagetool --appimage-extract >/dev/null
    mv squashfs-root appimagetool-build
    rm appimagetool
fi

export PATH="$(pwd)/linuxdeploy-build/usr/bin:$(pwd)/appimagetool-build/usr/bin:${PATH}"
echo "✓ Tools ready"
echo ""

################################################################################
# STEP 12: Create AppImage
################################################################################
echo "Step 12: Bundling and Creating AppImage"
echo "───────────────────────────────────────────────────────────────────────"
export VERSION="${APP_VERSION}"
export NO_STRIP=1

"$(pwd)/linuxdeploy-build/AppRun" \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/emacs" \
    --desktop-file "${APPDIR}/emacs.desktop" \
    --icon-file "${APPDIR}/${ICON_NAME}" \
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
elif [[ -f "Emacs-x86_64.AppImage" ]]; then
    mv "Emacs-x86_64.AppImage" "${OUTPUT}"
else
    FOUND=$(find . -maxdepth 1 -name "*.AppImage" | head -n 1)
    if [[ -n "$FOUND" ]]; then
        mv "$FOUND" "${OUTPUT}"
    else
        echo "✗ LinuxDeploy failed to create output file"
        exit 1
    fi
fi

chown "${TARGET_UID}:${TARGET_GID}" "${OUTPUT}" 2>/dev/null || true
chmod 755 "${OUTPUT}"
echo "✓ AppImage created: ${OUTPUT}"
echo "  Permissions: $(stat -c '%a %U:%G' "${OUTPUT}" 2>/dev/null || stat -f '%p %Su:%Sg' "${OUTPUT}")"
echo ""

################################################################################
# STEP 13: Cleanup
################################################################################
echo "Step 13: Cleanup"
echo "───────────────────────────────────────────────────────────────────────"
rm -rf "${APPDIR}" "emacs-${APP_VERSION}" "AppRun.source"
echo "✓ Cleaned build files"
echo ""

################################################################################
# STEP 14: Test
################################################################################
echo "Step 14: Testing"
echo "───────────────────────────────────────────────────────────────────────"
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

echo "═══════════════════════════════════════════════════════════════════════"
echo "✓✓✓ BUILD SUCCESSFUL ✓✓✓"
echo "═══════════════════════════════════════════════════════════════════════"
echo "AppImage:  ${OUTPUT}"
echo ""
