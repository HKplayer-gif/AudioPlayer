# Audio Player

A lightweight, offline-first macOS audio player with pitch and playback-speed processing.

## Requirements

- macOS 14 or later
- Apple Silicon build/release target for the currently prepared release artifact
- Xcode Command Line Tools with Swift 6.2 toolchain for building from source

The distributed app bundles its FFmpeg executable and required non-system dynamic libraries. End users do not need Homebrew, FFmpeg, or another package manager installed. macOS system frameworks remain platform requirements.

## Build from source

```sh
swift build
swift build -c release
```

## Package a release DMG

The repository does not store FFmpeg executable/library binaries. Prepare a self-contained FFmpeg runtime directory containing `ffmpeg`, all required non-system `*.dylib` files, and any applicable third-party notices. Verify the binaries' corresponding source and license obligations before distribution.

```sh
FFMPEG_RUNTIME_DIR="/absolute/path/to/ffmpeg-runtime" Scripts/package-release.sh
```

The script builds the release executable, creates `Audio Player.app`, sets the UI/bundle version metadata, checks linked libraries for non-portable absolute paths, verifies the bundled default-settings resource, checks that no personal user data is packaged, signs ad hoc, and writes `Audio Player v4.50.3.dmg` to `~/Downloads` by default. Override `OUTPUT_DIR` to choose another output folder. The app resolves its SwiftPM resource bundle from the packaged app resources and does not require the build-machine `.build` directory at runtime.

The current script's ad-hoc signature is not Developer ID signing and does not notarize the app. A public download may therefore show macOS Gatekeeper warnings until a Developer ID certificate and notarization workflow are configured.

## User data and privacy

User settings, playback history, library selections, playlists, and queue state are stored in the user's Application Support directory at runtime. Release packaging does not copy that directory or any local user data into the app or DMG. Do not commit personal media, user settings/state JSON, signing credentials, or local build artifacts.

## Third-party components

See `THIRD_PARTY_NOTICES.md` and the license texts under `Sources/AudioPlayer/Resources/ThirdPartyLicenses/`. FFmpeg is built with GPL components in the currently prepared runtime; maintain the corresponding source and all applicable notices when redistributing that runtime.

## License and attribution

The Audio Player project is licensed under the MIT License; see [`LICENSE`](LICENSE). You may use, modify, and redistribute the project under its terms. When redistributing copies or substantial portions, retain the copyright notice and the MIT license text.

Please also credit the original project and link back to this repository when publishing a redistribution or derivative. This is a project attribution request; the standard MIT license itself requires preservation of its copyright and license notice, but does not independently require a visible repository URL.

Third-party components are **not** relicensed under the project MIT license. Their original license terms and source-code obligations continue to apply; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and the bundled license texts.
