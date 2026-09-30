#!/usr/bin/env bash
# Packages a signed, stapled StockDock.app into a signed, notarized and stapled
# DMG with the drag-to-Applications layout from dmg/.
#
#   scripts/make-dmg.sh path/to/StockDock.app StockDock.dmg
#
# The ZIP stays the format for Sparkle and Homebrew; the DMG is for people who
# download from the website.
set -euo pipefail

APP="${1:?usage: make-dmg.sh <StockDock.app> <out.dmg>}"
OUT="${2:?usage: make-dmg.sh <StockDock.app> <out.dmg>}"
SIGNING_IDENTITY="Developer ID Application: Simone Ruggiero (M6TP9DBCVL)"
NOTARY_PROFILE="notarytool"

cd "$(dirname "$0")/.."
if [[ -f .env.release ]]; then
    source .env.release
fi
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }
[[ -f dmg/background.tiff ]] || python3 dmg/make-background.py

rm -f "$OUT"
uvx --quiet --from dmgbuild dmgbuild -s dmg/settings.py -D app="$APP" "StockDock" "$OUT"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$OUT"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "$ASC_KEY_ID" && -n "$ASC_ISSUER_ID" && -f "$ASC_KEY_PATH" ]]; then
    xcrun notarytool submit "$OUT" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
else
    echo "No notarization credentials (see release.sh)" >&2
    exit 1
fi

xcrun stapler staple "$OUT"
spctl --assess --type open --context context:primary-signature -v "$OUT"
echo "$OUT"
