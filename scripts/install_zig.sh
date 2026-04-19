#!/usr/bin/env bash

# QwD Script
# Purpose: Downloads and installs the Zig compiler (v0.13.0) for the current OS and architecture.
# Usage: ./scripts/install_zig.sh
# Expected Output: Zig installed at /usr/local/zig and added to the user's PATH.

set -e

ZIG_VERSION="0.13.0"

# Detect OS
OS=$(uname -s)
case "$OS" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *) echo "Unsupported OS"; exit 1 ;;
esac

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="aarch64" ;;
  *) echo "Unsupported architecture"; exit 1 ;;
esac

FILE="zig-${OS}-${ARCH}-${ZIG_VERSION}.tar.xz"
URL="https://ziglang.org/download/${ZIG_VERSION}/${FILE}"

echo "Downloading Zig ${ZIG_VERSION} for ${OS}-${ARCH}..."

curl -L "$URL" -o "$FILE"

# Verify file size
SIZE=$(wc -c < "$FILE")

if [ "$SIZE" -lt 1000000 ]; then
  echo "Download failed or incorrect file."
  echo "Downloaded file is too small (${SIZE} bytes)."
  exit 1
fi

echo "Extracting..."

tar -xf "$FILE"

DIR="zig-${OS}-${ARCH}-${ZIG_VERSION}"

# CLEAN REINSTALL: Remove existing installation to prevent corruption
if [ -d "/usr/local/zig" ]; then
  echo "Removing existing Zig installation at /usr/local/zig..."
  sudo rm -rf /usr/local/zig
fi

sudo mv "$DIR" /usr/local/zig
rm "$FILE"

echo "Adding Zig to PATH..."

SHELL_CONFIG="$HOME/.zshrc"

if [ -n "$BASH_VERSION" ]; then
  SHELL_CONFIG="$HOME/.bashrc"
fi

if ! grep -q "/usr/local/zig" "$SHELL_CONFIG"; then
  echo 'export PATH="/usr/local/zig:$PATH"' >> "$SHELL_CONFIG"
fi

echo
echo "Zig installed at /usr/local/zig"
echo "Run:"
echo "source $SHELL_CONFIG"
echo
echo "Test with:"
echo "zig version"
