# Third-party notices

Audio Player incorporates or distributes the following third-party components:

- **SoundTouch** — LGPL-2.1; license text: `Vendor/SoundTouch/COPYING.txt` and the bundled `SoundTouch-LGPL-2.1.txt`.
- **Signalsmith Stretch** — MIT; see `Vendor/SignalsmithStretch/LICENSE.txt`.
- **Signalsmith linear helper** — MIT; see `Vendor/SignalsmithStretch/SIGNALSMITH-LINEAR-LICENSE.txt`.
- **FFmpeg runtime** — FFmpeg 9.0.2 bundled runtime, configured with `--enable-gpl` and `--enable-version3`; the resulting FFmpeg build is subject to GPLv3 terms. Upstream project: https://ffmpeg.org/ . See the bundled FFmpeg license texts.
- The FFmpeg build also links external libraries. Versions reported by the local Homebrew environment used for this bundle include: x264 r3222, x265 4.3, LAME 4.0, Opus 1.6.1, libvpx 1.17.0, dav1d 1.5.4, SVT-AV1 4.2.0, libvmaf 3.2.1, OpenSSL 3.6.4, xz 5.8.4, and mpg123 1.33.7. Their license texts are included where available under `Sources/AudioPlayer/Resources/ThirdPartyLicenses/`; each component retains its own license and source obligations.

**Distribution condition:** the FFmpeg binary and external libraries are not source files in this repository. Before publishing the prepared DMG publicly, provide or maintain access to the exact corresponding source code and required notices for the exact binaries shipped, including applicable FFmpeg and external-library source/build modifications. A version label or upstream homepage alone is not a substitute for corresponding-source compliance.

The application bundle includes license texts and build identification information. Review the exact `ffmpeg -buildconf` output and all bundled dylib dependencies before each release.
