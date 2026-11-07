#!/bin/bash
# Publie une release GitHub : build, DMG, signature Sparkle (EdDSA), appcast.xml, `gh release create`.
# Prérequis : `gh` authentifié, clé EdDSA Sparkle dans le trousseau (generate_keys), VERSION à jour.
set -euo pipefail
cd "$(dirname "$0")"

REPO="goyan/super-volume"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
DMG="build/SuperVolume-$VERSION.dmg"
APPCAST="build/appcast.xml"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

./build.sh

SIG="$("$SIGN_UPDATE" "$DMG")"   # -> sparkle:edSignature="…" length="…"
cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SuperVolume</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/SuperVolume-$VERSION.dmg"
                 type="application/octet-stream" $SIG/>
    </item>
  </channel>
</rss>
EOF

gh release create "$TAG" "$DMG" "$APPCAST" --repo "$REPO" \
    --title "SuperVolume $VERSION" --generate-notes
echo "Release publiée : https://github.com/$REPO/releases/tag/$TAG"
