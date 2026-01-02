#!/bin/bash

# Source the main script to get the BUILD_DEPS array
source build-emacs-appimage.sh

# Use the BUILD_DEPS array from the main script
packages=("${BUILD_DEPS[@]}")

# Check if packages exist in Arch Linux
for pkg in "${packages[@]}"; do
  if pacman -Ss "^$pkg$" > /dev/null 2>&1; then
    echo "✓ $pkg"
  else
    echo "✗ $pkg (not found)"
  fi
done
