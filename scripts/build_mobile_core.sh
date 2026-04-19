#!/bin/bash
set -e

# QwD Mobile Core Builder
# Generates static libraries for macOS and iOS/iPadOS

# 1. Build for macOS (Host)
echo "Building QwD Static Core for macOS (arm64)..."
/usr/local/zig/zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast

# 2. Build for iPadOS/iOS
echo "Building QwD Static Core for iPadOS (arm64)..."
/usr/local/zig/zig build -Dtarget=aarch64-ios -Doptimize=ReleaseFast

echo "------------------------------------------------"
echo "Build Complete."
echo "Artifacts are in zig-out/lib/"
echo "Open apps/dashboard/QwD.xcodeproj to continue."
