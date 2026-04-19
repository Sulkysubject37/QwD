#!/bin/bash
set -e

# Configuration
ZIG="/Users/sulky/.zvm/master/zig"
PROJECT_ROOT=$(pwd)/../..
DASHBOARD_ROOT=$(pwd)
ZIG_OUT="$PROJECT_ROOT/zig-out"
FRAMEWORK_DIR="$DASHBOARD_ROOT/Frameworks"
XCFRAMEWORK="$FRAMEWORK_DIR/QwD.xcframework"

echo "--- QwD Dashboard Build: macOS Shared XCFramework ---"

rm -rf "$ZIG_OUT"
mkdir -p "$FRAMEWORK_DIR"
rm -rf "$XCFRAMEWORK"

cd "$PROJECT_ROOT"

# Build QwD as a shared library for macOS
echo "Building QwD Core (macOS Shared)..."
$ZIG build -Dtarget=aarch64-macos -Doptimize=ReleaseFast

# Create XCFramework using the dylib
echo "Creating XCFramework from dylib..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -create-xcframework \
    -library "$ZIG_OUT/lib/libqwd.dylib" \
    -headers "$DASHBOARD_ROOT/Sources/CQwD" \
    -output "$XCFRAMEWORK"

echo "Success! macOS XCFramework created at $XCFRAMEWORK"
