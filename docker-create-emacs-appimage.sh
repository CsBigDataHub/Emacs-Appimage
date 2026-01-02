#!/bin/bash

# Wrapper script for building Emacs AppImage in Docker

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/build"
OUTPUT_DIR="$(pwd)"
APP_VERSION="30.2"
OUTPUT="emacs-${APP_VERSION}-x86_64.AppImage"

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

# Build the container command with all required dependencies
CONTAINER_CMD=(
    "pacman -Syu --noconfirm \
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
      libwebp \
      gcc-libs \
      systemd-libs \
      sqlite \
      harfbuzz \
      libx11 \
      libxcb \
      libxext \
      libxrender \
      libxfixes \
      libxi \
      libxinerama \
      libxrandr \
      libxcursor \
      libxcomposite \
      libxdamage \
      libxxf86vm \
      libxau \
      libxdmcp \
      pcre2 \
      libffi \
      wayland \
      libxkbcommon \
      librsvg \
      gmp \
      mpfr \
      mpc \
      acl \
      attr \
      dbus \
      gtk-layer-shell \
      libtool \
      texinfo \
      automake \
      autoconf \
      bison \
      flex \
      libgccjit \
      webkit2gtk \
      webkit2gtk-4.1 \
      tree-sitter \
      appstream-glib \
      appstream \
      imagemagick \
      && chmod +x build-emacs-appimage.sh \
      && ./build-emacs-appimage.sh"
)

# Add arguments if specified
if [[ -n "${ICON_URL}" ]]; then
    CONTAINER_CMD+=("--icon" "${ICON_URL}")
fi
if [[ "${APP_VERSION}" != "30.2" ]]; then
    CONTAINER_CMD+=("--version" "${APP_VERSION}")
fi
if [[ "${OUTPUT}" != "emacs-${APP_VERSION}-x86_64.AppImage" ]]; then
    CONTAINER_CMD+=("--output" "${OUTPUT}")
fi

# Join the container command with && and quotes
CONTAINER_CMD_STR=$(printf "%s && " "${CONTAINER_CMD[@]}")
CONTAINER_CMD_STR="${CONTAINER_CMD_STR% && }"

# Execute the Docker command
docker run -it --rm \
    -v "${SCRIPT_DIR}:${BUILD_DIR}" \
    -w "${BUILD_DIR}" \
    archlinux \
    /bin/bash -c "${CONTAINER_CMD_STR}"

# Copy the output file to the current directory if it was created
if [[ -f "${BUILD_DIR}/${OUTPUT}" ]]; then
    cp "${BUILD_DIR}/${OUTPUT}" "${OUTPUT_DIR}/"
    echo "AppImage copied to: ${OUTPUT_DIR}/${OUTPUT}"
fi
