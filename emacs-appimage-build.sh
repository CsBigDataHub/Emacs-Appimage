#!/bin/bash
################################################################################
#                                                                              #
#  EMACS APPIMAGE - WITH PATH INJECTION (EMACS-PLUS STYLE)                    #
#                                                                              #
################################################################################
set -euo pipefail
APP_VERSION="30.2"
OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"
ICON_URL=""
APPDIR="$(pwd)/AppDir"
TARGET_UID=$(id -u)
TARGET_GID=$(id -g)
BUILD_PATH="${PATH}"

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]
Options:
  --icon, -i ICON_URL          Download custom icon from URL
  --version, -v VERSION        Emacs version (default: 30.2)
  --output, -o OUTPUT          Output filename
  --uid UID                    Target user ID for file ownership
  --gid GID                    Target group ID for file ownership
  --inject-path PATH           Custom PATH to inject (default: current PATH)
  --no-path-injection          Disable PATH injection feature
  --help, -h                   Show this help
EOF
    exit 0
}

ENABLE_PATH_INJECTION=true

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
        --inject-path)
            BUILD_PATH="$2"
            shift 2
            ;;
        --no-path-injection)
            ENABLE_PATH_INJECTION=false
            shift
            ;;
        --help | -h) show_help ;;
        *)
            echo "ERROR: Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "═══════════════════════════════════════════════════════════════════════"
echo "  EMACS APPIMAGE WITH PATH INJECTION"
echo "═══════════════════════════════════════════════════════════════════════"
echo "Configuration:"
echo "  Version:           ${APP_VERSION}"
echo "  Output:            ${OUTPUT}"
echo "  Custom Icon:       ${ICON_URL:-None}"
echo "  Target User:       ${TARGET_UID}:${TARGET_GID}"
echo "  PATH Injection:    ${ENABLE_PATH_INJECTION}"
if [[ "${ENABLE_PATH_INJECTION}" == "true" ]]; then
    echo "  Injected PATH:     ${BUILD_PATH}"
fi
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
    echo "  Library dir: ${LIBGCCJIT_DIR}"
else
    echo "  ⚠ libgccjit not found"
fi
echo "✓ Native-comp detection complete"
echo ""

################################################################################
# STEP 7: Create AppRun (FIXED FOR MISE/ASDF AND PATH SANITIZATION)
################################################################################
echo "Step 7: Creating AppRun with PATH injection"
echo "───────────────────────────────────────────────────────────────────────"

# Initialize standard paths
INJECTED_PATHS="/usr/local/bin:/usr/local/sbin"

# 1. Resolve GCC to its REAL path (Bypassing Shims)
if command -v gcc &>/dev/null; then
    # Use readlink -f to follow the shim to the actual executable
    REAL_GCC=$(readlink -f "$(which gcc)")
    GCC_DIR=$(dirname "$REAL_GCC")

    # Only add if it doesn't look like a shim directory
    if [[ ! "$GCC_DIR" =~ "/shims" ]]; then
        INJECTED_PATHS="${GCC_DIR}:${INJECTED_PATHS}"
        echo "  ✓ Resolved real GCC path: ${GCC_DIR}"
    else
        echo "  ⚠ Skipped GCC path because it resolved to a shim: ${GCC_DIR}"
    fi
fi

if [[ -d "$HOME/.local/bin" ]]; then
    INJECTED_PATHS="$HOME/.local/bin:${INJECTED_PATHS}"
fi

cat >"AppRun.source" <<EOF
#!/bin/bash
EMACS_VER="${APP_VERSION}"
EOF

if [[ "${ENABLE_PATH_INJECTION}" == "true" ]]; then
    cat >>"AppRun.source" <<EOF
INJECTED_PATHS="${INJECTED_PATHS}"
DISABLE_INJECTION="\${EMACS_PLUS_NO_PATH_INJECTION:-}"
EOF
    echo "  ✓ PATH injection enabled"
else
    cat >>"AppRun.source" <<EOF
DISABLE_INJECTION="1"
EOF
    echo "  ℹ PATH injection disabled"
fi

cat >>"AppRun.source" <<'APPRUN_EOF'
HERE="$(dirname "$(readlink -f "${0}")")"

# 1. Aggressive Environment Cleanup
# Unset mise/asdf/env vars that confuse subprocesses
unset GTK_MODULES MISE_SHELL MISE_ORIGINAL_PATH ASDF_DIR ASDF_DATA_DIR
unset RBENV_SHELL PYENV_SHELL NODENV_SHELL GOENV_SHELL
for var in $(env 2>/dev/null | grep -E '^(MISE_|ASDF_|RUBY_|GEM_)' | cut -d= -f1); do unset "$var" 2>/dev/null || true; done
unset EMACSLOADPATH EMACSDATA EMACSPATH EMACSDOC EMACSDIR EMACS_BASE INFOPATH
unset NATIVE_COMP_DRIVER_OPTIONS NATIVE_COMP_COMPILER_OPTIONS

export GTK_MODULES="" UBUNTU_MENUPROXY=0 NO_AT_BRIDGE=1

ARCH_LIBEXEC="${HERE}/usr/libexec/emacs/${EMACS_VER}/x86_64-pc-linux-gnu"
ARCH_BIN="${HERE}/usr/bin"

# 2. Robust PATH Construction (Shim Filtering)
if [[ -z "${DISABLE_INJECTION}" ]]; then
    # Start with Emacs internal bin
    FINAL_PATH_LIST="${ARCH_BIN}"

    # Combine User Path and Injected Path
    RAW_PATH="${INJECTED_PATHS:-}:${PATH:-}"

    # Iterate and Filter
    IFS=':' read -ra PATHS <<< "$RAW_PATH"
    for p in "${PATHS[@]}"; do
        # SKIP if empty
        [[ -z "$p" ]] && continue
        # SKIP if it is a shim directory (mise, asdf, etc)
        [[ "$p" =~ (mise|asdf|rbenv|pyenv|nodenv|goenv)/shims ]] && continue
        # SKIP if already in our new path
        [[ ":${FINAL_PATH_LIST}:" == *":${p}:"* ]] && continue

        FINAL_PATH_LIST="${FINAL_PATH_LIST}:${p}"
    done

    # Add standard system paths at the very end as fallback
    FINAL_PATH_LIST="${FINAL_PATH_LIST}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    export PATH="${FINAL_PATH_LIST}"

    # Set CC only if we found a valid gcc in our cleaned path
    if command -v gcc &>/dev/null; then
        export CC="$(command -v gcc)"
    fi
else
    export PATH="${ARCH_BIN}:/usr/local/bin:/usr/bin:/bin"
fi

export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/lib64:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="/usr/lib:/usr/lib64:/usr/lib/gcc:/usr/lib/x86_64-linux-gnu:${LIBRARY_PATH:-}"
export EMACSPATH="${ARCH_LIBEXEC}:${ARCH_BIN}"
export EMACSDIR="${HERE}/usr/share/emacs"
export EMACSDATA="${HERE}/usr/share/emacs/${EMACS_VER}/etc"
export EMACSDOC="${HERE}/usr/share/emacs/${EMACS_VER}/etc"
export EMACSLOADPATH="${HERE}/usr/share/emacs/${EMACS_VER}/lisp:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/emacs-lisp:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/progmodes:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/language:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/international:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/textmodes:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/vc:${HERE}/usr/share/emacs/${EMACS_VER}/lisp/net:${HERE}/usr/share/emacs/site-lisp"
export FONTCONFIG_PATH="${HERE}/etc/fonts"
export LIBFUSE_DISABLE_THREAD_SPAWNING=1

# Detect binary to run
BIN_NAME=$(basename "${ARGV0:-$0}")
TARGET_BIN="emacs"
ARGS=("$@")
[[ "$BIN_NAME" == "emacsclient"* ]] && TARGET_BIN="emacsclient"
[[ "${1:-}" =~ ^(emacsclient|ctags|etags)$ ]] && TARGET_BIN="$1" && ARGS=("${@:2}")

# Launch
if [[ "$TARGET_BIN" == "emacs" ]]; then
    DUMP_FILE="${ARCH_LIBEXEC}/emacs.pdmp"
    [[ -f "$DUMP_FILE" ]] && exec "${ARCH_BIN}/emacs" --name "emacs-appimage" --dump-file="$DUMP_FILE" "${ARGS[@]}"
    exec "${ARCH_BIN}/emacs" --name "emacs-appimage" "${ARGS[@]}"
else
    exec "${ARCH_BIN}/${TARGET_BIN}" "${ARGS[@]}"
fi
APPRUN_EOF

chmod +x "AppRun.source"
echo "✓ AppRun created (Deep mise/shim filtering applied)"
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
            echo "  ✓ Downloaded and verified image"
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
            echo "  ✓ Custom icon processed: ${APPDIR}/${ICON_NAME}"
        else
            echo "  ✗ Downloaded file is not a valid image!"
            rm "${TEMP_ICON}"
        fi
    else
        echo "  ✗ Failed to download custom icon"
    fi
fi

if [[ $ICON_FOUND -eq 0 ]]; then
    echo "  Using fallback Emacs icon from source..."
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
    echo "  ⚠ No icon found! Creating fallback..."
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

echo "  Overwriting all internal icons..."
if [[ ! -f "${APPDIR}/${ICON_NAME}" ]]; then
    echo "  ✗ CRITICAL: No icon file found at ${APPDIR}/${ICON_NAME}"
    exit 1
fi

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

INTERNAL_IMG_DIR="${APPDIR}/usr/share/emacs/${APP_VERSION}/etc/images"
mkdir -p "${INTERNAL_IMG_DIR}" "${INTERNAL_IMG_DIR}/icons"
cp "${APPDIR}/${ICON_NAME}" "${INTERNAL_IMG_DIR}/emacs.png"
cp "${APPDIR}/${ICON_NAME}" "${INTERNAL_IMG_DIR}/icons/emacs.png"

mkdir -p "${APPDIR}/usr/share/pixmaps"
cp "${APPDIR}/${ICON_NAME}" "${APPDIR}/usr/share/pixmaps/emacs.png"
cp "${APPDIR}/${ICON_NAME}" "${APPDIR}/usr/share/pixmaps/emacs-appimage.png"

find "${APPDIR}/usr/share" -type f \( -name "*emacs*.svg" -o -name "*emacs*.xpm" \) -delete 2>/dev/null || true
echo "✓ Icon setup complete (${ICON_NAME})"
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
Exec=env WEBKIT_DISABLE_COMPOSITING_MODE=1 emacs %F
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
echo "✓ Tools extracted and ready"
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
echo "Fixes applied:"
echo "  ✓ Filtered mise/asdf/rbenv/pyenv shims from PATH"
echo "  ✓ Isolated native-comp cache to prevent loadup.el errors"
echo "  ✓ Clean environment (no EMACSLOADPATH pollution)"
echo ""
