#!/usr/bin/env bash
#
# Refresh the bundled VIA keyboards manifest from the upstream repo.
#
# Clones (or pulls) https://github.com/the-via/keyboards into reference/via-keyboards,
# walks v3/**/*.json, and writes Sources/LayerLensCore/Resources/via_keyboards_manifest.json.
#
# Run from the repo root:
#   ./Tools/refresh_via_manifest.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CHECKOUT_DIR="reference/via-keyboards"
OUT="Sources/LayerLensCore/Resources/via_keyboards_manifest.json"

if [ -d "$CHECKOUT_DIR/.git" ]; then
    echo "Updating $CHECKOUT_DIR ..."
    git -C "$CHECKOUT_DIR" fetch --depth=1 origin master
    git -C "$CHECKOUT_DIR" reset --hard origin/master
else
    echo "Cloning the-via/keyboards into $CHECKOUT_DIR ..."
    mkdir -p "$(dirname "$CHECKOUT_DIR")"
    git clone --depth=1 https://github.com/the-via/keyboards.git "$CHECKOUT_DIR"
fi

PRE_SIZE=0
PRE_COUNT=0
if [ -f "$OUT" ]; then
    PRE_SIZE=$(wc -c < "$OUT" | tr -d ' ')
    PRE_COUNT=$(python3 -c "import json; print(len(json.load(open('$OUT'))))")
fi

echo "Building manifest -> $OUT"
python3 "Tools/build_via_manifest.py" "$CHECKOUT_DIR" "$OUT"

POST_SIZE=$(wc -c < "$OUT" | tr -d ' ')
POST_COUNT=$(python3 -c "import json; print(len(json.load(open('$OUT'))))")

echo
echo "Manifest refreshed."
echo "  boards: $PRE_COUNT -> $POST_COUNT"
echo "  size:   $PRE_SIZE B -> $POST_SIZE B"
echo
echo "Review with: git diff --stat $OUT"
echo "Commit when satisfied."
