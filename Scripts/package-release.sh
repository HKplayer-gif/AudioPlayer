#!/bin/bash
set -euo pipefail

VERSION="26.11.1"
BUILD_NUMBER="26.11.1"
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
if [[ ! -f "$ROOT/AudioPlayer.icns" ]]; then
    echo "ERROR: App icon missing from $ROOT/AudioPlayer.icns" >&2
    exit 2
fi

cd "$ROOT"
"$ROOT/Scripts/build-essentia.sh"
swift build -c release
BINARY="$ROOT/.build/release/AudioPlayer"
RESOURCE_BUNDLE="$ROOT/.build/release/AudioPlayer_AudioPlayer.bundle"
[[ -x "$BINARY" ]] || { echo "ERROR: Release executable not found: $BINARY" >&2; exit 3; }
[[ -d "$RESOURCE_BUNDLE" ]] || { echo "ERROR: SwiftPM resource bundle not found: $RESOURCE_BUNDLE" >&2; exit 3; }

# Start from a clean, version-specific staging directory so stale files from an
# earlier packaging attempt cannot leak into this release.
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
cp "$ROOT/AudioPlayer.icns" "$RESOURCES/AudioPlayer.icns"

# Bundle FFmpeg and its runtime dylibs. The release app must not resolve Homebrew paths.
cp "$FFMPEG_RUNTIME_DIR/ffmpeg" "$RESOURCES/ffmpeg"
chmod 755 "$RESOURCES/ffmpeg"
find "$FFMPEG_RUNTIME_DIR" -maxdepth 1 -type f -name '*.dylib' -exec cp -f {} "$RESOURCES/" \;

# Include the project's third-party notices and license texts in the app bundle.
for license_file in \
    AudioPlayer-AGPL-3.0.txt \
    Essentia-AGPL-3.0.txt \
    FFmpeg-LICENSE.md \
    FFmpeg-COPYING-LGPLv2.1.txt \
    LAME-LICENSE.txt \
    mpg123-COPYING.txt \
    SoundTouch-LGPL-2.1.txt \
    SignalsmithLinear-MIT.txt \
    SignalsmithStretch-MIT.txt; do
    cp "$ROOT/Sources/AudioPlayer/Resources/ThirdPartyLicenses/$license_file" "$RESOURCES/ThirdPartyLicenses/"
done
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/ThirdPartyLicenses/THIRD_PARTY_NOTICES.md"
cp "$ROOT/NOTICE" "$RESOURCES/NOTICE"
if [[ -d "$FFMPEG_RUNTIME_DIR/ThirdPartyLicenses" ]]; then
    find "$FFMPEG_RUNTIME_DIR/ThirdPartyLicenses" -maxdepth 1 -type f -exec cp -f {} "$RESOURCES/ThirdPartyLicenses/" \;
fi
cat > "$RESOURCES/ThirdPartyLicenses/FFmpeg-Build-Info.txt" <<EOF
FFmpeg runtime bundled with Audio Player v${VERSION}.
Upstream: https://ffmpeg.org/
Build version: $("$RESOURCES/ffmpeg" -version 2>&1 | head -1)
Build configuration: $("$RESOURCES/ffmpeg" -buildconf 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's#/opt/homebrew/Cellar/ffmpeg/9.0.2#<build-prefix>#g')
This build is configured without GPL, nonfree, or OpenSSL components.
FFmpeg is LGPL-2.1-or-later; libmp3lame and mpg123 retain their own licenses.
See FFmpeg-LICENSE.md, FFmpeg-COPYING-LGPLv2.1.txt, LAME-LICENSE.txt, and mpg123-COPYING.txt.
The bundled runtime is self-contained and has no Homebrew or build-machine runtime dependency.
Corresponding source and build records are supplied with this release.
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
# Replace only the artifact for this exact release version.
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING_DIR" -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

# Mount the completed image read-only and verify its actual delivered contents.
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/audioplayer-dmg-check.XXXXXX")"
cleanup_mount() {
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup_mount EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
MOUNTED_APP="$MOUNT_DIR/${APP_NAME}.app"
[[ -d "$MOUNTED_APP" ]] || { echo "ERROR: App bundle missing from mounted DMG." >&2; exit 5; }
[[ -L "$MOUNT_DIR/Applications" ]] || { echo "ERROR: Applications shortcut missing from mounted DMG." >&2; exit 5; }
[[ -f "$MOUNTED_APP/Contents/Resources/AudioPlayer.icns" ]] || { echo "ERROR: App icon missing from mounted DMG." >&2; exit 5; }
[[ -x "$MOUNTED_APP/Contents/Resources/ffmpeg" ]] || { echo "ERROR: Bundled FFmpeg missing from mounted DMG." >&2; exit 5; }
[[ "$(find "$MOUNTED_APP/Contents/Resources" -maxdepth 1 -type f -name '*.dylib' | wc -l | tr -d ' ')" -ge 1 ]] || { echo "ERROR: Bundled FFmpeg libraries missing from mounted DMG." >&2; exit 5; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNTED_APP/Contents/Info.plist")" == "$VERSION" ]] || { echo "ERROR: Mounted DMG version mismatch." >&2; exit 5; }
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR"
trap - EXIT

# Verify version metadata and the expected self-contained export backend.
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == "$BUNDLE_ID" ]]
[[ -x "$RESOURCES/ffmpeg" ]]
[[ -f "$RESOURCES/libmp3lame.0.dylib" ]]
[[ -f "$RESOURCES/libmpg123.0.dylib" ]]
[[ -f "$RESOURCES/AudioPlayer_AudioPlayer.bundle/Default Settings.json" ]]
"$RESOURCES/ffmpeg" -version >/dev/null
"$RESOURCES/ffmpeg" -L 2>&1 | grep -q "Lesser General Public License" || { echo "ERROR: FFmpeg license configuration is not the expected LGPL build." >&2; exit 4; }
if "$RESOURCES/ffmpeg" -buildconf 2>&1 | grep -Eq -- '--enable-(gpl|nonfree|openssl)'; then
    echo "ERROR: FFmpeg build enables a restricted GPL/nonfree/OpenSSL configuration." >&2
    exit 4
fi
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
