#!/bin/bash
set -e

# Configuration
PROJECT_NAME="QwD"
SCHEME="QwDDashboard"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
DASHBOARD_ROOT=$(pwd)

# Default simulator if none specified
SIM_DEVICE=${1:-"iPhone 15"}

echo "--- Phase Ubi-Gen: Universal Build & Simulator Deployment ---"

# 1. Ensure XCFramework exists
if [ ! -d "Frameworks/QwD.xcframework" ]; then
    echo "XCFramework not found. Running build_xcframework.sh..."
    ./build_xcframework.sh
fi

# 2. Build for Simulator
echo "Building for Simulator ($SIM_DEVICE)..."
$DEVELOPER_DIR/usr/bin/xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$SIM_DEVICE" \
    -configuration Debug \
    ONLY_ACTIVE_ARCH=NO \
    build \
    DEVELOPER_DIR="$DEVELOPER_DIR"

# 3. Boot Simulator if needed
SIM_ID=$($DEVELOPER_DIR/usr/bin/simctl list devices available | grep "$SIM_DEVICE" | head -n 1 | awk -F '[()]' '{print $2}')

if [ -z "$SIM_ID" ]; then
    echo "Error: Device '$SIM_DEVICE' not found."
    exit 1
fi

echo "Booting Simulator ($SIM_DEVICE: $SIM_ID)..."
$DEVELOPER_DIR/usr/bin/simctl boot "$SIM_ID" 2>/dev/null || true
open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app

# 4. Install and Launch
echo "Installing and Launching on Simulator..."
APP_PATH=$( $DEVELOPER_DIR/usr/bin/xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$SIM_DEVICE" \
    -configuration Debug \
    -showBuildSettings | grep " BUILT_PRODUCTS_DIR =" | awk '{print $3}' )

APP_BUNDLE="$APP_PATH/$SCHEME.app"

$DEVELOPER_DIR/usr/bin/simctl install "$SIM_ID" "$APP_BUNDLE"
$DEVELOPER_DIR/usr/bin/simctl launch "$SIM_ID" "com.sulky.QwDDashboard"

echo "Success! QwD Dashboard launched on $SIM_DEVICE."
