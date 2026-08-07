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

# Build a universal binary so one .app runs on both Apple Silicon and Intel.
ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "==> Building universal release binary (arm64 + x86_64)"
cd "$ROOT"
swift build -c release --product LayerLens "${ARCH_FLAGS[@]}"

# Multi-arch builds land in .build/apple/Products/Release, NOT .build/release
# (that path is a single-triple symlink and would silently hand us a thin
# binary). Ask SPM for the real output dir instead of hardcoding it; the
# embedded-framework and resource-bundle globs below depend on it too.
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/LayerLens"

if [[ ! -x "$BIN" ]]; then
    echo "Expected built binary at $BIN, but it's missing or non-executable." >&2
    exit 1
fi

# Fail loudly if either slice is missing (e.g. an arch flag got dropped) —
# we'd rather break the release than ship a thin binary mislabelled universal.
ARCHS="$(lipo -archs "$BIN")"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
    echo "Binary at $BIN is not universal (got: $ARCHS)." >&2
    exit 1
fi
echo "    Architectures: $ARCHS"

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
for framework in "$BIN_DIR/"*.framework; do
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
for bundle in "$BIN_DIR/"*.bundle; do
    [[ -d "$bundle" ]] || continue
    # Current toolchains (Swift 6.3 / Xcode 26) emit resource bundles with the
    # standard macOS layout, i.e. the resources live under Contents/Resources/.
    # Older ones put them straight in the bundle root, so pick whichever side
    # actually holds the files. Getting this wrong nests them at
    # Contents/Resources/Contents/Resources/..., where Bundle.main can't find
    # them; loadBundledManifest then falls through to Bundle.module, which
    # fatalErrors because the SPM bundle isn't in the .app at all. The app
    # launches fine and only dies when a keyboard is connected.
    src="$bundle"
    if [[ -d "$bundle/Contents/Resources" ]]; then
        src="$bundle/Contents/Resources"
    fi
    # Copying "$src/." rather than "$src"/* keeps this working for bundles with
    # no resources at all. Several dependencies ship a PrivacyInfo.xcprivacy,
    # so those collide and the last one wins — harmless for a distribution
    # that never goes through App Store review.
    cp -R "$src/." "$APP/Contents/Resources/"
    echo "    Flattened resources from: $(basename "$bundle")"
done
shopt -u nullglob

# Verify the flattening actually landed. An .app missing the VIA manifest
# builds without complaint and only fails once a user plugs a keyboard in,
# so fail the build here rather than ship something silently broken.
MANIFEST="$APP/Contents/Resources/via_keyboards_manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
    echo "Expected the VIA manifest at $MANIFEST after flattening SPM resource bundles, but it's missing." >&2
    exit 1
fi

echo "==> Bundle ready: $APP"
ls -la "$APP/Contents"
