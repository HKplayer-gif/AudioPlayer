#!/bin/bash
set -euo pipefail

VERSION="4.50.3"
BUILD_NUMBER="4503"
APP_NAME="Audio Player"
BUNDLE_ID="com.audioplayer"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Downloads}"
FFMPEG_RUNTIME_DIR="${FFMPEG_RUNTIME_DIR:-}"
STAGING_DIR="$OUTPUT_DIR/.AudioPlayer-v${VERSION}-staging"
APP_DIR="$STAGING_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
RESOURCES="$CONTENTS/Resources"

if [[ -z "$FFMPEG_RUNTIME_DIR" || ! -x "$FFMPEG_RUNTIME_DIR/ffmpeg" ]]; then
    echo "ERROR: Set FFMPEG_RUNTIME_DIR to a self-contained FFmpeg runtime directory." >&2
    echo "It must contain an executable 'ffmpeg' and every required non-system .dylib." >&2
    exit 2
fi
if [[ ! -f "$ROOT/Sources/AudioPlayer/Resources/AudioPlayer.icns" ]]; then
    echo "ERROR: App icon missing from Sources/AudioPlayer/Resources/AudioPlayer.icns" >&2
    exit 2
fi

cd "$ROOT"
swift build -c release
BINARY="$ROOT/.build/release/AudioPlayer"
RESOURCE_BUNDLE="$ROOT/.build/release/AudioPlayer_AudioPlayer.bundle"
[[ -x "$BINARY" ]] || { echo "ERROR: Release executable not found: $BINARY" >&2; exit 3; }
[[ -d "$RESOURCE_BUNDLE" ]] || { echo "ERROR: SwiftPM resource bundle not found: $RESOURCE_BUNDLE" >&2; exit 3; }

rm -rf "$STAGING_DIR"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES/ThirdPartyLicenses"
cp "$BINARY" "$CONTENTS/MacOS/AudioPlayer"
cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"
# The app resolves defaults from this in-bundle resource bundle. Never rely on
# SwiftPM's generated absolute .build path at runtime.
[[ -f "$RESOURCES/AudioPlayer_AudioPlayer.bundle/Default Settings.json" ]] || {
    echo "ERROR: Default Settings.json is missing from the packaged resource bundle." >&2
    exit 3
}
cp "$ROOT/Sources/AudioPlayer/Resources/AudioPlayer.icns" "$RESOURCES/AudioPlayer.icns"

# Bundle FFmpeg and its runtime dylibs. The release app must not resolve Homebrew paths.
cp "$FFMPEG_RUNTIME_DIR/ffmpeg" "$RESOURCES/ffmpeg"
chmod 755 "$RESOURCES/ffmpeg"
find "$FFMPEG_RUNTIME_DIR" -maxdepth 1 -type f -name '*.dylib' -exec cp -f {} "$RESOURCES/" \;

# Include the project's third-party notices and license texts in the app bundle.
find "$ROOT/Sources/AudioPlayer/Resources/ThirdPartyLicenses" -maxdepth 1 -type f -exec cp -f {} "$RESOURCES/ThirdPartyLicenses/" \;
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/ThirdPartyLicenses/THIRD_PARTY_NOTICES.md"
if [[ -d "$FFMPEG_RUNTIME_DIR/ThirdPartyLicenses" ]]; then
    find "$FFMPEG_RUNTIME_DIR/ThirdPartyLicenses" -maxdepth 1 -type f -exec cp -f {} "$RESOURCES/ThirdPartyLicenses/" \;
fi
cat > "$RESOURCES/ThirdPartyLicenses/FFmpeg-Build-Info.txt" <<EOF
FFmpeg runtime bundled with Audio Player v${VERSION}.
Upstream: https://ffmpeg.org/
Build version: $("$RESOURCES/ffmpeg" -version 2>&1 | head -1)
Build configuration: $("$RESOURCES/ffmpeg" -buildconf 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's#/opt/homebrew/Cellar/ffmpeg/9.0.2#<build-prefix>#g')
This build enables GPL components. See FFmpeg-LICENSE.md and FFmpeg-COPYING-GPLv3.txt.
Corresponding source and external-library source availability must be maintained with this release.
EOF

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>AudioPlayer</string>
    <key>CFBundleIconFile</key><string>AudioPlayer</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# A drag-to-Applications layout; no personal data or local Application Support files are copied.
ln -s /Applications "$STAGING_DIR/Applications"
plutil -lint "$CONTENTS/Info.plist"

# Reject accidental links to Homebrew or other non-system absolute paths.
while IFS= read -r binary; do
    otool -L "$binary" | tail -n +2 | awk '{print $1}' | while IFS= read -r dependency; do
        case "$dependency" in
            /System/Library/*|/usr/lib/*|@loader_path/*|@rpath/*|@executable_path/*) ;;
            *) echo "ERROR: Non-portable dependency in $binary: $dependency" >&2; exit 1;;
        esac
    done
done < <(find "$CONTENTS/MacOS" "$RESOURCES" -maxdepth 1 -type f \( -name 'AudioPlayer' -o -name 'ffmpeg' -o -name '*.dylib' \) -print)

# Ad-hoc signing permits local verification but is not Developer ID notarization.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

DMG_PATH="$OUTPUT_DIR/${APP_NAME} v${VERSION}.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

# Verify version metadata and the expected self-contained export backend.
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == "$BUNDLE_ID" ]]
[[ -x "$RESOURCES/ffmpeg" ]]
[[ -f "$RESOURCES/AudioPlayer_AudioPlayer.bundle/Default Settings.json" ]]
if find "$APP_DIR" \( -name "User Data" -o -name "User Settings.json" -o -name "Playback History.json" \) -print -quit | grep -q .; then
    echo "ERROR: Personal user data was found inside the release app bundle." >&2
    exit 4
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "Release DMG created: $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
echo "App bundle: $APP_DIR"
echo "Bundle ID: $BUNDLE_ID | Version: $VERSION | Build: $BUILD_NUMBER"
echo "Note: ad-hoc signed; Developer ID signing/notarization is not configured."
