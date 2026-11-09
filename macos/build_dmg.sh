#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/SpanShot.app"
MACOS_BIN_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
DMG_STAGE="$BUILD_DIR/dmg_stage"
DMG_OUT="$BUILD_DIR/SpanShot.dmg"
MODULE_CACHE="/tmp/spanshot-swift-module-cache"

echo "==> Cleaning previous build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_BIN_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

echo "==> Generating Info.plist (NSHighResolutionCapable=true)..."
cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SpanShot</string>
    <key>CFBundleDisplayName</key>
    <string>SpanShot</string>
    <key>CFBundleIdentifier</key>
    <string>com.steeefanie.spanshot</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>SpanShot</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SpanShot 需要屏幕录制权限以捕获屏幕选区并拼接横纵长截图。</string>
</dict>
</plist>
EOF

SOURCES=("$SCRIPT_DIR"/Sources/*.swift)

echo "==> Compiling SpanShot Universal Binary (arm64 + x86_64) with swiftc -O..."
if swiftc -O -target arm64-apple-macosx14.0 -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$BUILD_DIR/SpanShot_arm64" && \
   swiftc -O -target x86_64-apple-macosx14.0 -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$BUILD_DIR/SpanShot_x86_64"; then
    lipo -create -output "$MACOS_BIN_DIR/SpanShot" "$BUILD_DIR/SpanShot_arm64" "$BUILD_DIR/SpanShot_x86_64"
    rm -f "$BUILD_DIR/SpanShot_arm64" "$BUILD_DIR/SpanShot_x86_64"
else
    echo "Fallback to native host architecture compilation..."
    swiftc -O -target arm64-apple-macosx14.0 -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$MACOS_BIN_DIR/SpanShot"
fi

chmod +x "$MACOS_BIN_DIR/SpanShot"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Running automated self-test suite (--self-test)..."
"$MACOS_BIN_DIR/SpanShot" --self-test

echo "==> Packaging SpanShot.dmg via hdiutil..."
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/SpanShot.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "SpanShot" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_OUT"
rm -rf "$DMG_STAGE"

echo "==> Successfully built: $DMG_OUT"
ls -lh "$DMG_OUT"
