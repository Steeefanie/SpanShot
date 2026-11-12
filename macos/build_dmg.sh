#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/SpanShot.app"
MACOS_BIN_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICNS_FILE="$BUILD_DIR/AppIcon.icns"
DMG_BG_DIR="$BUILD_DIR/dmg_bg"
DMG_STAGE="$BUILD_DIR/dmg_stage"
APP_VERSION="${SPANSHOT_VERSION:-1.2.0}"
APP_VERSION="${APP_VERSION#v}"
DMG_UNIVERSAL_OUT="$BUILD_DIR/SpanShot_v${APP_VERSION}_Universal.dmg"
DMG_ARM64_OUT="$BUILD_DIR/SpanShot_v${APP_VERSION}_AppleSilicon.dmg"
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

echo "==> Generating Retina DMG installer background (background.tiff)..."
"$BUILD_DIR/SpanShot_arm64" --generate-dmg-bg "$DMG_BG_DIR"
/usr/bin/tiffutil -cathidpicheck "$DMG_BG_DIR/bg.png" "$DMG_BG_DIR/bg@2x.png" -out "$DMG_BG_DIR/background.tiff"

echo "==> Running automated self-test suite (--self-test)..."
"$BUILD_DIR/SpanShot_arm64" --self-test

package_dmg() {
    local bin_src="$1"
    local vol_name="$2"
    local dmg_dest="$3"
    local rw_dmg="$BUILD_DIR/rw_temp.dmg"

    # Detach any existing mounted volume with the same name
    if [ -d "/Volumes/$vol_name" ]; then
        hdiutil detach "/Volumes/$vol_name" -force >/dev/null 2>&1 || true
    fi

    cp "$bin_src" "$MACOS_BIN_DIR/SpanShot"
    chmod +x "$MACOS_BIN_DIR/SpanShot"
    codesign --force --deep -i com.steeefanie.spanshot --sign - "$APP_DIR" >/dev/null 2>&1 || true

    rm -rf "$DMG_STAGE" "$rw_dmg" "$dmg_dest"
    mkdir -p "$DMG_STAGE/.background"
    cp -R "$APP_DIR" "$DMG_STAGE/SpanShot.app"
    ln -s /Applications "$DMG_STAGE/Applications"
    cp "$DMG_BG_DIR/background.tiff" "$DMG_STAGE/.background/background.tiff"
    cp "$ICNS_FILE" "$DMG_STAGE/.VolumeIcon.icns"

    # Create read-write DMG for Finder layout customization
    hdiutil create -volname "$vol_name" -srcfolder "$DMG_STAGE" -ov -format UDRW -fs HFS+ "$rw_dmg" >/dev/null

    local mount_dir="/Volumes/$vol_name"
    hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg" -mountpoint "$mount_dir" >/dev/null

    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "$mount_dir" 2>/dev/null || true
        SetFile -a V "$mount_dir/.background" 2>/dev/null || true
        SetFile -a V "$mount_dir/.VolumeIcon.icns" 2>/dev/null || true
    fi

    # Configure Finder window size (660x400 content), 128px large icons, background arrow, and Left -> Right positions
    /usr/bin/osascript <<OSA || true
tell application "Finder"
    tell disk "$vol_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 14
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "SpanShot.app" of container window to {180, 178}
        set position of item "Applications" of container window to {480, 178}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

    sync
    hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || hdiutil detach "$mount_dir" >/dev/null 2>&1
    hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_dest" >/dev/null
    rm -rf "$DMG_STAGE" "$rw_dmg"
}

echo "==> Packaging Apple Silicon DMG ($DMG_ARM64_OUT)..."
package_dmg "$BUILD_DIR/SpanShot_arm64" "SpanShot (Apple Silicon)" "$DMG_ARM64_OUT"

echo "==> Packaging Universal Binary DMG ($DMG_UNIVERSAL_OUT)..."
package_dmg "$BUILD_DIR/SpanShot_universal" "SpanShot" "$DMG_UNIVERSAL_OUT"

rm -rf "$BUILD_DIR/SpanShot_arm64" "$BUILD_DIR/SpanShot_x86_64" "$BUILD_DIR/SpanShot_universal" "$ICNS_FILE" "$DMG_BG_DIR"

echo "==> Build completed successfully:"
ls -lh "$DMG_ARM64_OUT" "$DMG_UNIVERSAL_OUT"
