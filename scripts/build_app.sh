#!/bin/sh
# Build GhostX.app from Swift Package Manager binary
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/GhostX.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building Swift package..."
cd "$PROJECT_DIR/src"
swift build -c release 2>&1

BINARY="$PROJECT_DIR/src/.build/arm64-apple-macosx/release/GhostX"
if [ ! -f "$BINARY" ]; then
    BINARY="$PROJECT_DIR/src/.build/debug/GhostX"
    echo "Using debug build: $BINARY"
fi

echo "Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS_DIR/GhostX"

# PkgInfo
echo "APPL????" > "$CONTENTS/PkgInfo"

# Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>GhostX</string>
    <key>CFBundleIdentifier</key>
    <string>com.ghostx.app</string>
    <key>CFBundleName</key>
    <string>GhostX</string>
    <key>CFBundleDisplayName</key>
    <string>GhostX</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Entitlements for sandbox
cat > "$BUILD_DIR/GhostX.entitlements" << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
ENT

# Copy libghostty-vt dylib if present
DYLIB="$(find "$PROJECT_DIR/build/ghostty/lib" -name "*.dylib" 2>/dev/null | head -1)"
if [ -n "$DYLIB" ]; then
    cp "$DYLIB" "$MACOS_DIR/"
    echo "Copied libghostty-vt dylib"
fi

echo "App bundle created at $APP_DIR"
echo "Run with: open $APP_DIR"