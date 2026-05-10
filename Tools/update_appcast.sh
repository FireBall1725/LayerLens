#!/usr/bin/env bash
#
# Append a new <item> to appcast.xml for a freshly built dmg. Called from
# .github/workflows/release.yml between notarisation and the GH release
# publish step. Idempotent for a given version (re-running won't double up).
#
#     Tools/update_appcast.sh <version> <dmg-path> <ed-signature>

set -euo pipefail

VERSION="${1:?usage: $0 <version> <dmg-path> <ed-signature>}"
DMG_PATH="${2:?missing dmg path}"
ED_SIG="${3:?missing EdDSA signature}"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "DMG not found at $DMG_PATH" >&2
    exit 1
fi

LENGTH=$(stat -f %z "$DMG_PATH")
PUB_DATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
URL="https://github.com/FireBall1725/LayerLens/releases/download/v${VERSION}/LayerLens-${VERSION}.dmg"
APPCAST="appcast.xml"

if [[ ! -f "$APPCAST" ]]; then
    echo "$APPCAST not found at repo root" >&2
    exit 1
fi

# Hand the heavy lifting to Python; XML rewrites are easier there than in
# sed. We pass everything via env vars so the heredoc stays unquoted-friendly.
export VERSION URL LENGTH PUB_DATE ED_SIG APPCAST
python3 <<'PY'
import os, re

version  = os.environ["VERSION"]
url      = os.environ["URL"]
length   = os.environ["LENGTH"]
pub_date = os.environ["PUB_DATE"]
ed_sig   = os.environ["ED_SIG"]
appcast  = os.environ["APPCAST"]

with open(appcast, "r", encoding="utf-8") as f:
    content = f.read()

# Drop any prior <item> for the same version (so re-running the workflow
# on the same tag won't accumulate duplicates).
content = re.sub(
    rf"\s*<item>\s*<title>Version {re.escape(version)}</title>.*?</item>",
    "",
    content,
    flags=re.DOTALL,
)

new_item = f"""        <item>
            <title>Version {version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="{url}"
                length="{length}"
                type="application/octet-stream"
                sparkle:edSignature="{ed_sig}" />
        </item>
"""

marker = "<!-- The release workflow inserts new <item> entries above this comment. -->"
content = content.replace(marker, new_item + "        " + marker)

with open(appcast, "w", encoding="utf-8") as f:
    f.write(content)
PY

echo "==> appcast.xml updated for v${VERSION}"
grep "<title>Version " "$APPCAST" | head -5
