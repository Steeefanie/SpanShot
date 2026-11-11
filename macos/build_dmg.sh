#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/SpanShot.app"
MACOS_BIN_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICNS_FILE="$BUILD_DIR/AppIcon.icns"
DMG_STAGE="$BUILD_DIR/dmg_stage"
APP_VERSION="${SPANSHOT_VERSION:-1.1.0}"
APP_VERSION="${APP_VERSION#v}"
DMG_UNIVERSAL_OUT="$BUILD_DIR/SpanShot_v${APP_VERSION}_macOS_Universal.dmg"
DMG_ARM64_OUT="$BUILD_DIR/SpanShot_v${APP_VERSION}_macOS_AppleSilicon.dmg"
MODULE_CACHE="/tmp/spanshot-swift-module-cache"

echo "==> Cleaning previous build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_BIN_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

echo "==> Generating Info.plist (version=$APP_VERSION, NSHighResolutionCapable=true, CFBundleIconFile=AppIcon)..."
cat > "$APP_DIR/Contents/Info.plist" << EOF
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
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>SpanShot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
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

echo "==> Compiling SpanShot for Apple Silicon (arm64)..."
swiftc -O -target arm64-apple-macosx14.0 -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$BUILD_DIR/SpanShot_arm64"
chmod +x "$BUILD_DIR/SpanShot_arm64"

echo "==> Compiling SpanShot for Intel (x86_64) & creating Universal Binary..."
if swiftc -O -target x86_64-apple-macosx14.0 -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$BUILD_DIR/SpanShot_x86_64"; then
    lipo -create -output "$BUILD_DIR/SpanShot_universal" "$BUILD_DIR/SpanShot_arm64" "$BUILD_DIR/SpanShot_x86_64"
    chmod +x "$BUILD_DIR/SpanShot_universal"
else
    cp "$BUILD_DIR/SpanShot_arm64" "$BUILD_DIR/SpanShot_universal"
fi

echo "==> Generating macOS AppIcon.icns from vector renderer..."
"$BUILD_DIR/SpanShot_arm64" --generate-iconset "$ICONSET_DIR"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
cp "$ICNS_FILE" "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> Running automated self-test suite (--self-test)..."
"$BUILD_DIR/SpanShot_arm64" --self-test

package_dmg() {
    local bin_src="$1"
    local vol_name="$2"
    local dmg_dest="$3"

    cp "$bin_src" "$MACOS_BIN_DIR/SpanShot"
    chmod +x "$MACOS_BIN_DIR/SpanShot"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

    rm -rf "$DMG_STAGE"
    mkdir -p "$DMG_STAGE"
    cp -R "$APP_DIR" "$DMG_STAGE/SpanShot.app"
    cp "$ICNS_FILE" "$DMG_STAGE/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "$DMG_STAGE" 2>/dev/null || true
    fi
    ln -s /Applications "$DMG_STAGE/Applications"

    hdiutil create -volname "$vol_name" -srcfolder "$DMG_STAGE" -ov -format UDZO "$dmg_dest"
    rm -rf "$DMG_STAGE"
}

echo "==> Packaging Apple Silicon DMG ($DMG_ARM64_OUT)..."
package_dmg "$BUILD_DIR/SpanShot_arm64" "SpanShot (Apple Silicon)" "$DMG_ARM64_OUT"

echo "==> Packaging Universal Binary DMG ($DMG_UNIVERSAL_OUT)..."
package_dmg "$BUILD_DIR/SpanShot_universal" "SpanShot" "$DMG_UNIVERSAL_OUT"

rm -f "$BUILD_DIR/SpanShot_arm64" "$BUILD_DIR/SpanShot_x86_64" "$BUILD_DIR/SpanShot_universal" "$ICNS_FILE"

echo "==> Build completed successfully:"
ls -lh "$DMG_ARM64_OUT" "$DMG_UNIVERSAL_OUT"
