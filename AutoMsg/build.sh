#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources/AutoMsg"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="AutoMsg"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk")

echo "Building $APP_NAME..."
echo "SDK: $SDK"

mkdir -p "$BUILD_DIR"

SWIFT_FILES=$(find "$SOURCES_DIR" -name "*.swift" -type f)

swiftc \
    -o "$BUILD_DIR/$APP_NAME" \
    -sdk "$SDK" \
    -target arm64-apple-macosx14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework Contacts \
    -lsqlite3 \
    -parse-as-library \
    $SWIFT_FILES

echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Generate icon if missing
if [ ! -f "$PROJECT_DIR/AppIcon.icns" ]; then
    echo "Generating app icon..."
    swift "$PROJECT_DIR/generate_icon.swift" "$PROJECT_DIR"
fi
cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AutoMsg</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.automsg.app</string>
    <key>CFBundleName</key>
    <string>AutoMsg</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>AutoMsg needs to send messages via Messages.app</string>
    <key>NSContactsUsageDescription</key>
    <string>AutoMsg uses your Contacts to display names instead of phone numbers</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>AutoMsg runs a local HTTP server so you can control it from your iPhone on the same WiFi</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo ""
echo "Build complete!"
echo "  App: $APP_BUNDLE"
echo ""
echo "To run: open '$APP_BUNDLE'"
echo "Or double-click AutoMsg.app in Finder"
