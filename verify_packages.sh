#!/bin/bash

# List of packages to verify
packages=(
  "base-devel"
  "git"
  "wget"
  "curl"
  "ca-certificates"
  "gtk3"
  "gnutls"
  "ncurses"
  "libxml2"
  "libjpeg-turbo"
  "libpng"
  "libtiff"
  "libwebp"
  "gcc-libs"
  "systemd-libs"
  "sqlite"
  "harfbuzz"
  "libx11"
  "libxcb"
  "libxext"
  "libxrender"
  "libxfixes"
  "libxi"
  "libxinerama"
  "libxrandr"
  "libxcursor"
  "libxcomposite"
  "libxdamage"
  "libxxf86vm"
  "libxau"
  "libxdmcp"
  "pcre2"
  "libffi"
  "wayland"
  "libxkbcommon"
  "librsvg"
  "gmp"
  "mpfr"
  "mpc"
  "acl"
  "attr"
  "libselinux"
  "dbus"
  "gtk-layer-shell"
  "libtool"
  "texinfo"
  "automake"
  "autoconf"
  "bison"
  "flex"
)

# Check if packages exist in Arch Linux
for pkg in "${packages[@]}"; do
  if pacman -Ss "^$pkg$" > /dev/null 2>&1; then
    echo "✓ $pkg"
  else
    echo "✗ $pkg (not found)"
  fi
done
