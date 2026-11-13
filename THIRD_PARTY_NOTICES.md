# Third-party notices

Audio Player incorporates or distributes the following third-party components:

- **SoundTouch** — LGPL-2.1; license text: `Vendor/SoundTouch/COPYING.txt` and `SoundTouch-LGPL-2.1.txt`.
- **Signalsmith Stretch** — MIT; see `Vendor/SignalsmithStretch/LICENSE.txt`.
- **Signalsmith linear helper** — MIT; see `Vendor/SignalsmithStretch/SIGNALSMITH-LINEAR-LICENSE.txt`.
- **Essentia 2.1_beta5** (pinned commit `ed59cc48e37ac33ac15b252fc5ad7af4b9ecd51d`) — GNU AGPL-3.0; statically linked into Audio Player. The application calls `KeyExtractor` and `RhythmExtractor2013`. The macOS build uses the lightweight configuration and Accelerate FFT, with no Python bindings or pretrained models. License text: `Vendor/Essentia/COPYING.txt` and bundled `Essentia-AGPL-3.0.txt`.
- **FFmpeg 9.0.2** — LGPL-2.1-or-later build, configured without `--enable-gpl`, `--enable-nonfree`, or `--enable-openssl`. Native FFmpeg audio codecs are used alongside the LAME MP3 encoder. Upstream project: https://ffmpeg.org/ . See `FFmpeg-LICENSE.md` and `FFmpeg-COPYING-LGPLv2.1.txt`.
- **LAME 4.0** — LGPL; dynamically linked by FFmpeg as `libmp3lame.0.dylib`.
- **mpg123 1.33.7** — LGPL; a dynamic dependency of the prepared LAME library (`libmpg123.0.dylib`).

The FFmpeg runtime includes only the FFmpeg libraries, LAME, mpg123, and macOS system frameworks. OpenSSL and the former GPL video codec libraries are not included in this release runtime. Exact FFmpeg/LAME/mpg123 source archives, runtime hashes, configure options, and build provenance are included in the `Audio Player v26.11.1 FFmpeg Source Materials.tar.gz` release asset.

The application bundle includes the applicable license texts and build identification information. The distributed app does not require Homebrew, Python, FFmpeg, or any other separately installed runtime package.

## Project license transition

The AGPL-3.0 licensing transition was prepared during the v4.51.4 development test on 2026-11-12. The current public release, v26.11.1, is distributed under GNU AGPL-3.0-only. Earlier published releases through v4.50.4 remain under MIT; see `LICENSE-MIT-PRIOR-RELEASES.txt` for the prior license text.

The project license does not replace or remove the individual licenses of bundled third-party components. Each dependency's exact version, build configuration, source availability, and license must be recorded for every binary release.

## Essentia build details

The pinned Essentia source is included as the Vendor/Essentia Git submodule. Audio Player's build script applies the local macOS SDK / deployment-target compatibility patch and builds a static library for macOS 14.0 or later using Accelerate. The resulting library is linked into the Audio Player executable; it is not loaded as a separate runtime dylib.

The selected Essentia build includes its NNLS Chroma and Cephes source components. Their original source attribution remains in the Essentia source tree and must be retained in corresponding-source distributions. The submodule also contains upstream components that are not linked into this configured binary; their original license files remain in the source tree.
