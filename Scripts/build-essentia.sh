#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ESSENTIA="$ROOT/Vendor/Essentia"
PATCH="$ROOT/Patches/Essentia/0001-macos-sdk-libcxx-headers.patch"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

if [[ ! -f "$ESSENTIA/waf" ]]; then
    echo "ERROR: Essentia source is missing. Initialize Git submodules first." >&2
    exit 1
fi

if ! git -C "$ESSENTIA" diff --quiet -- wscript; then
    if ! grep -q "Audio Player build compatibility" "$ESSENTIA/wscript"; then
        echo "ERROR: Vendor/Essentia/wscript has unexpected local modifications." >&2
        exit 1
    fi
else
    patch -p1 -d "$ESSENTIA" < "$PATCH"
fi

# Bootstrap Waf's embedded runtime, then adapt its removed Python 3.11 'U' mode.
(
    cd "$ESSENTIA"
    python3 waf --help >/dev/null 2>&1 || true
)

python3 - "$ESSENTIA" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
runtime_files = list(root.glob(".waf3-*/waflib/Utils.py"))
if not runtime_files:
    raise SystemExit("Waf runtime was not generated; cannot apply Python compatibility patch.")

for path in runtime_files:
    source = path.read_text()
    anchor = "def readf(fname,m='r',encoding='latin-1'):\n"
    if anchor not in source:
        if "m=m.replace('U', '')" in source:
            continue
        raise SystemExit(f"Unsupported Waf runtime layout: {path}")
    if "m=m.replace('U', '')" not in source:
        source = source.replace(
            anchor,
            anchor + "\tm=m.replace('U', '')  # Python 3.11 removed universal-newline mode.\n",
            1
        )
        path.write_text(source)
PY

cd "$ESSENTIA"
SDKROOT="$SDKROOT" MACOSX_DEPLOYMENT_TARGET=14.0 python3 waf configure \
    --build-static \
    --lightweight= \
    --fft=ACCELERATE \
    --ignore-algos=Spline,CubicSpline \
    --no-msse \
    --prefix="$ROOT/.build/essentia-install"

python3 waf -j2

LIBRARY="$ESSENTIA/build/src/libessentia.a"
if [[ ! -s "$LIBRARY" ]]; then
    echo "ERROR: Essentia static library was not produced." >&2
    exit 1
fi

echo "Essentia static library ready: $LIBRARY"
