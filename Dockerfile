# Use the official Arch Linux image
FROM archlinux

# Set environment variables
ENV APP_VERSION=29.4
ENV APP_NAME=Emacs
ENV APP_DIR=AppDir
ENV OUTPUT=emacs-${APP_VERSION}-x86_64.AppImage

# Install build dependencies
RUN pacman -Syu --noconfirm \
    base-devel \
    git \
    wget \
    curl \
    ca-certificates \
    gtk3 \
    gnutls \
    ncurses \
    libxml2 \
    libjpeg-turbo \
    libpng \
    libtiff \
    giflib \
    librsvg \
    libwebp \
    gcc \
    systemd \
    sqlite3 \
    harfbuzz \
    libxi \
    libxkbfile \
    libxmu \
    libxt \
    libxpm \
    libxaw \
    libxft \
    libxrender \
    libxext \
    libx11 \
    xcb-util \
    pkgconf \
    texinfo \
    libtool \
    automake \
    autoconf \
    bison \
    flex \
    gmp \
    mpfr \
    mpc \
    acl \
    attr \
    dbus \
    libgccjit \
    tree-sitter \
    xorgproto

# Install AppImage tools
RUN wget -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" \
    && chmod +x linuxdeploy-x86_64.AppImage \
    && mv linuxdeploy-x86_64.AppImage /usr/local/bin/linuxdeploy \
    && wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" \
    && chmod +x appimagetool-x86_64.AppImage \
    && mv appimagetool-x86_64.AppImage /usr/local/bin/appimagetool

# Create build directory
RUN mkdir -p /build
WORKDIR /build

# Download and extract Emacs source
RUN wget -c "https://ftp.gnu.org/gnu/emacs/emacs-${APP_VERSION}.tar.xz" \
    && tar -xf "emacs-${APP_VERSION}.tar.xz" \
    && rm -f "emacs-${APP_VERSION}.tar.xz"

# Configure and build Emacs
WORKDIR /build/emacs-${APP_VERSION}
RUN ./configure \
    --disable-build-details \
    --with-modules \
    --with-pgtk \
    --with-cairo \
    --with-compress-install \
    --with-toolkit-scroll-bars \
    --with-native-compilation=aot \
    --with-tree-sitter \
    --with-xinput2 \
    --with-dbus \
    --with-harfbuzz \
    --with-libsystemd \
    --with-sqlite3 \
    --prefix=/usr \
    "CFLAGS=-O2 -pipe -fomit-frame-pointer -DFD_SETSIZE=10000"

RUN make -j"$(nproc)" bootstrap \
    && make -j"$(nproc)" \
    && make install DESTDIR=/build/${APP_DIR}

# Create AppRun script
RUN cat > /build/${APP_DIR}/AppRun << 'EOF'
#!/bin/bash

# Debug logging
LOG_FILE="$HOME/emacs-appimage-run.log"
exec > >(tee -a "$LOG_FILE") 2>&1

export PATH="/usr/bin:${PATH}"
export LD_LIBRARY_PATH="/usr/lib:${LD_LIBRARY_PATH}"
export EMACSDATA="/usr/share/emacs"
export EMACSLOADPATH="/usr/share/emacs/site-lisp"

# Run Emacs
exec "/usr/bin/emacs" "$@"
EOF

RUN chmod +x /build/${APP_DIR}/AppRun

# Create desktop entry
RUN cat > /build/${APP_DIR}/emacs.desktop << EOF
[Desktop Entry]
Name=Emacs
Exec=AppRun
Icon=emacs
Type=Application
Categories=Utility;TextEditor;
Terminal=false
StartupWMClass=Emacs
EOF

# Bundle libraries
RUN mkdir -p /build/${APP_DIR}/usr/lib \
    && cp -r /usr/lib/libgtk* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgdk* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libglib* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgobject* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgio* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgthread* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libpango* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libcairo* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libfontconfig* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libfreetype* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libharfbuzz* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libpng* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libjpeg* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libtiff* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libwebp* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/librsvg* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgcc_s.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libstdc++* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libm.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libc.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libdl.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libpthread.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/librt.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libresolv.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libz.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libbz2.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/liblzma.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libselinux.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libacl.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libattr.so* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libdbus* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libsystemd* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libsqlite3* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgmp* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libmpfr* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libmpc* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libgccjit* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libxcb* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libX11* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXext* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXrender* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXfixes* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXi* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXtst* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXinerama* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXrandr* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXcursor* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXcomposite* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXdamage* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXxf86vm* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXau* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libXdmcp* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libxkbcommon* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libwayland* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libffi* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libpcre* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libiconv* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libintl* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libxml2* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/liblz4* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libsnappy* /build/${APP_DIR}/usr/lib/ \
    && cp -r /usr/lib/libzstd* /build/${APP_DIR}/usr/lib/

# Create AppImage
WORKDIR /build
RUN /usr/local/bin/linuxdeploy --appdir ${APP_DIR} --output appimage

# Rename the output file
RUN mv *.AppImage ${OUTPUT}

# Copy the output file to the host
RUN mkdir -p /output && cp ${OUTPUT} /output/

# Set the output directory
WORKDIR /output
