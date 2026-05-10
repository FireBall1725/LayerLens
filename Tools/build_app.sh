#!/usr/bin/env bash
#
# Wrap the SPM-built LayerLens executable into a proper macOS .app bundle
# (Info.plist + Contents/MacOS/LayerLens). Run with the version string as
# the only argument:
#
#     Tools/build_app.sh 0.1.0
#
# The resulting bundle lands at dist/LayerLens.app. Code signing is handled
# by the caller (release.yml, or a developer running a follow-up codesign
# command locally). This script only does the bundle layout so the signing
# step has something to point `codesign` at.

set -euo pipefail

VERSION="${1:?usage: $0 <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/LayerLens.app"

echo "==> Building release binary"
cd "$ROOT"
swift build -c release --product LayerLens
BIN="$ROOT/.build/release/LayerLens"

if [[ ! -x "$BIN" ]]; then
    echo "Expected built binary at $BIN, but it's missing or non-executable." >&2
    exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Substitute the version into the Info.plist template.
sed "s/__VERSION__/${VERSION}/g" "$ROOT/Tools/Info.plist.in" > "$APP/Contents/Info.plist"

# Copy the binary into Contents/MacOS. CFBundleExecutable in Info.plist must
# match the filename here (we set both to "LayerLens").
cp "$BIN" "$APP/Contents/MacOS/LayerLens"
chmod +x "$APP/Contents/MacOS/LayerLens"

# Bundle icon. Info.plist references CFBundleIconFile = "AppIcon".
if [[ -f "$ROOT/Tools/Assets/AppIcon.icns" ]]; then
    cp "$ROOT/Tools/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Embed dynamic frameworks SPM produced (Sparkle ships as a binary
# xcframework). Without copying these into Contents/Frameworks/ the dyld
# loader can't find them at launch and the app crashes immediately.
mkdir -p "$APP/Contents/Frameworks"
shopt -s nullglob
for framework in "$ROOT/.build/release/"*.framework; do
    cp -R "$framework" "$APP/Contents/Frameworks/"
    echo "    Embedded framework: $(basename "$framework")"
done
shopt -u nullglob

# Flatten SPM resource bundles into Contents/Resources/. SPM ships per-target
# Resources via wrapper .bundle directories (e.g. LayerLensCore_LayerLensCore.bundle)
# whose Bundle.module accessor expects them at the root of Bundle.main,
# which for an .app would be the .app folder itself, breaking code signing
# (unsealed contents in bundle root). LayoutResolver.loadBundledManifest now
# checks Bundle.main first, so just dropping the JSON into the standard
# Contents/Resources/ is enough and keeps the .app structure clean.
shopt -s nullglob
for bundle in "$ROOT/.build/release/"*.bundle; do
    if [[ -d "$bundle" ]]; then
        cp -R "$bundle"/* "$APP/Contents/Resources/" 2>/dev/null || true
        echo "    Flattened resources from: $(basename "$bundle")"
    fi
done
shopt -u nullglob

echo "==> Bundle ready: $APP"
ls -la "$APP/Contents"
