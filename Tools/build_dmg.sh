#!/usr/bin/env bash
#
# Package dist/LayerLens.app into a polished drag-installer .dmg with custom
# icon positions, a background image, and a real /Applications shortcut that
# Finder renders with the actual Applications-folder icon (not a dashed
# placeholder, which is what `create-dmg --app-drop-link` ends up showing on
# some systems because it doesn't wait for Finder to resolve the symlink).
#
#     Tools/build_dmg.sh 0.1.0
#
# Expects build_app.sh to have already produced dist/LayerLens.app and the
# caller to have signed it. Output:
#
#     dist/LayerLens-<version>.dmg

set -euo pipefail

VERSION="${1:?usage: $0 <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/LayerLens.app"
DMG="$DIST/LayerLens-${VERSION}.dmg"
VOLNAME="LayerLens"
RW_DMG="$DIST/LayerLens-rw.dmg"
BACKGROUND="$ROOT/Tools/Assets/dmg-background.png"

if [[ ! -d "$APP" ]]; then
    echo "Expected $APP. Run Tools/build_app.sh first." >&2
    exit 1
fi

# Detach any leftover mount from a previous run, otherwise hdiutil can't
# attach a fresh image of the same volume name.
if [[ -d "/Volumes/$VOLNAME" ]]; then
    hdiutil detach -force "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
fi

rm -f "$DMG" "$RW_DMG"

echo "==> Building writable scratch dmg"
# UDRW = Read/Write so we can populate it; size leaves room for the .app + a
# little slack. Final converted dmg shrinks to actual content size.
APP_SIZE_KB=$(du -sk "$APP" | awk '{print $1}')
SLACK_KB=20480  # 20 MB headroom for the symlink, .DS_Store, background, etc.
TOTAL_KB=$((APP_SIZE_KB + SLACK_KB))
hdiutil create \
    -srcfolder "$APP" \
    -volname "$VOLNAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${TOTAL_KB}k" \
    "$RW_DMG"

echo "==> Mounting scratch dmg"
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
DEVICE=$(echo "$MOUNT_OUTPUT" | awk '/^\/dev\// {print $1; exit}')
MOUNT="/Volumes/$VOLNAME"

# Background image lives in a hidden folder Finder reads via the .DS_Store.
mkdir -p "$MOUNT/.background"
cp "$BACKGROUND" "$MOUNT/.background/background.png"

# /Applications shortcut. We use a *Finder alias* rather than a symlink:
# Finder aliases carry the target's icon resource embedded, so the mounted
# DMG renders the actual Applications folder icon. Symlinks rely on Finder
# resolving the target at display time, which is unreliable on freshly
# mounted DMGs and leaves a dashed-box placeholder.
osascript <<APPLESCRIPT
tell application "Finder"
    set destDisk to disk "$VOLNAME"
    set sourceFolder to folder "Applications" of (path to startup disk)
    make new alias file at destDisk to sourceFolder
    set name of result to "Applications"
end tell
APPLESCRIPT

# Hide the .app's bundle extension so the icon label reads "LayerLens", not
# "LayerLens.app". osascript can't reach this; SetFile is what AppKit's
# Finder actually consults via FinderInfo flags.
if command -v SetFile >/dev/null 2>&1; then
    SetFile -a E "$MOUNT/$(basename "$APP")"
fi

echo "==> Telling Finder how to lay things out"
# AppleScript routes the layout through Finder, which is the only path that
# (a) writes a .DS_Store the system trusts, and (b) makes Finder fully resolve
# the Applications symlink so it renders with the standard folder icon.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$(basename "$APP")" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Give Finder a moment to actually flush the .DS_Store before we detach.
sync
sleep 1

echo "==> Detaching"
hdiutil detach "$DEVICE" -force >/dev/null

echo "==> Converting to compressed read-only dmg"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW_DMG"

echo "==> DMG ready: $DMG"
ls -lh "$DMG"
