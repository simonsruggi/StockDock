#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
SCHEME="StockDock"
APP_NAME="StockDock"
BUNDLE_ID="com.simone.stockdock"
SIGNING_IDENTITY="Developer ID Application: Simone Ruggiero (M6TP9DBCVL)"
ENTITLEMENTS="StockDock.entitlements"
NOTARY_PROFILE="notarytool"
# Fallback when the keychain profile can't be used (a non-interactive shell
# cannot unlock the login keychain, so `notarytool store-credentials` and
# `--keychain-profile` both fail): submit with the App Store Connect API key.
# These identify an App Store Connect account, so they're read from the
# environment (or an untracked .env.release) rather than committed. The actual
# secret is the .p8 private key, which lives outside the repo either way.
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
SPARKLE_SIGN=".build/artifacts/sparkle/Sparkle/bin/sign_update"
APPCAST="appcast.xml"
PLIST="StockDock/Info.plist"
GITHUB_REPO="simonsruggi/StockDock"
HOMEBREW_TAP_CASK="/opt/homebrew/Library/Taps/simonsruggi/homebrew-tap/Casks/stockdock.rb"
BUILD_DIR=".build/xcode"
MIN_SYSTEM_VERSION="14.0"
PRODUCTS_DIR="${BUILD_DIR}/Build/Products/Release"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${GREEN}━━━ Step $1: $2 ━━━${NC}"; }

# --- Usage ---
if [[ $# -lt 2 ]]; then
    echo "Usage: ./release.sh <version> <build_number>"
    echo "  version:      marketing version (e.g. 1.1)"
    echo "  build_number:  integer build number for Sparkle (e.g. 2)"
    echo ""
    echo "Example: ./release.sh 1.1 2"
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
TAG="v${VERSION}"
ZIP_NAME="${APP_NAME}.zip"
APP_PATH="${PRODUCTS_DIR}/${APP_NAME}.app"

cd "$(dirname "$0")"

# Local, untracked overrides (App Store Connect key id / issuer id). Sourced
# after the cd so it's found regardless of where the script was invoked from,
# and guarded with `if` because `[[ ]] && source` would trip `set -e` when the
# file is absent — which is the normal case on a fresh clone.
if [[ -f .env.release ]]; then
    source .env.release
    ASC_KEY_ID="${ASC_KEY_ID:-}"
    ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
    ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
fi

# --- Preflight checks ---
step 0 "Preflight checks"

[[ -f "$PLIST" ]]           || fail "Info.plist not found at $PLIST"
[[ -f "$ENTITLEMENTS" ]]    || fail "Entitlements not found at $ENTITLEMENTS"
[[ -f "$SPARKLE_SIGN" ]]    || fail "Sparkle sign_update not found at $SPARKLE_SIGN"
[[ -f "$APPCAST" ]]         || fail "appcast.xml not found"
command -v xcrun >/dev/null  || fail "xcrun not found"
command -v gh >/dev/null     || fail "GitHub CLI (gh) not found"
command -v git >/dev/null    || fail "git not found"

if git tag -l "$TAG" | grep -q "$TAG"; then
    fail "Tag $TAG already exists. Bump the version or delete the tag first."
fi

if [[ -n "$(git status --porcelain)" ]]; then
    warn "Working directory has uncommitted changes."
    read -rp "Continue anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

info "Releasing ${APP_NAME} v${VERSION} (build ${BUILD_NUMBER})"

# --- Step 1: Bump version in Info.plist ---
step 1 "Bump version in Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PLIST"
info "CFBundleShortVersionString → ${VERSION}"
info "CFBundleVersion → ${BUILD_NUMBER}"

# --- Step 2: Build Release + assemble .app ---
step 2 "Build Release"

xcodebuild -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build 2>&1 | tail -5

BINARY="${PRODUCTS_DIR}/${APP_NAME}"
[[ -f "$BINARY" ]] || fail "Build failed: $BINARY not found"
info "Build succeeded: $BINARY"

info "Assembling ${APP_NAME}.app bundle"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/Frameworks"

cp "$BINARY" "$APP_PATH/Contents/MacOS/${APP_NAME}"
cp "$PLIST" "$APP_PATH/Contents/Info.plist"
cp "StockDock/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R "${PRODUCTS_DIR}/Sparkle.framework" "$APP_PATH/Contents/Frameworks/Sparkle.framework"

# Copy SPM resource bundles (fonts, assets)
for bundle in "${PRODUCTS_DIR}"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$APP_PATH/Contents/Resources/"
done

# Copy localization .lproj into the app's top-level Resources (Bundle.main),
# so SwiftUI's LocalizedStringKey lookups resolve the chosen in-app language.
for lproj in StockDock/Resources/*.lproj; do
    [[ -d "$lproj" ]] && cp -R "$lproj" "$APP_PATH/Contents/Resources/"
done

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_PATH/Contents/MacOS/${APP_NAME}"

info "App bundle assembled: $APP_PATH"

# --- Step 2b: Smoke test ---
step 2b "Smoke test (launch → 3s → check alive)"

"$APP_PATH/Contents/MacOS/${APP_NAME}" &
SMOKE_PID=$!
sleep 3
if kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    info "App launched and stayed alive for 3s"
else
    wait "$SMOKE_PID" 2>/dev/null || true
    fail "App crashed during smoke test — aborting release"
fi

# --- Step 3: Code-sign ---
step 3 "Code-sign"

codesign --deep --force --verify --verbose \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH" || fail "Code-sign verification failed"
info "Code-signed and verified"

# --- Step 4: Package ZIP ---
step 4 "Package ZIP"

rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_NAME"
ZIP_SIZE=$(stat -f%z "$ZIP_NAME")
info "Created $ZIP_NAME (${ZIP_SIZE} bytes)"

# --- Step 5: Notarize ---
step 5 "Notarize"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$ZIP_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
elif [[ -n "$ASC_KEY_ID" && -n "$ASC_ISSUER_ID" && -f "$ASC_KEY_PATH" ]]; then
    warn "Keychain profile '$NOTARY_PROFILE' unavailable — using the App Store Connect API key"
    xcrun notarytool submit "$ZIP_NAME" \
        --key "$ASC_KEY_PATH" \
        --key-id "$ASC_KEY_ID" \
        --issuer "$ASC_ISSUER_ID" \
        --wait
else
    fail "No notarization credentials: the '$NOTARY_PROFILE' keychain profile is unusable and no App Store Connect key was found. Set ASC_KEY_ID and ASC_ISSUER_ID (in the environment or in .env.release, which is gitignored) and make sure the .p8 exists."
fi

info "Notarization accepted"

# --- Step 6: Staple + re-zip ---
step 6 "Staple notarization ticket"

xcrun stapler staple "$APP_PATH"
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_NAME"
ZIP_SIZE=$(stat -f%z "$ZIP_NAME")
info "Re-packaged $ZIP_NAME with stapled ticket (${ZIP_SIZE} bytes)"

# --- Step 7: Sparkle EdDSA sign ---
step 7 "Sparkle EdDSA sign"

SIGN_OUTPUT=$("$SPARKLE_SIGN" "$ZIP_NAME")
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | cut -d'"' -f2)

if [[ -z "$ED_SIGNATURE" ]]; then
    echo "$SIGN_OUTPUT"
    fail "Could not extract edSignature from sign_update output"
fi

info "edSignature: ${ED_SIGNATURE}"

# --- Step 8: Update appcast.xml ---
step 8 "Update appcast.xml"

PUBDATE=$(date -R)
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_NAME}"

# Release notes ("What's New") shown by Sparkle — read from release-notes/<version>.html
NOTES_FILE="release-notes/${VERSION}.html"
if [[ -f "$NOTES_FILE" ]]; then
    DESCRIPTION_BLOCK="<description><![CDATA[
$(cat "$NOTES_FILE")
            ]]></description>"
    info "Release notes loaded from $NOTES_FILE"
else
    DESCRIPTION_BLOCK="<description>Version ${VERSION}</description>"
    warn "No release notes at $NOTES_FILE — using a placeholder description"
fi

cat > "$APPCAST" <<APPCAST_EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>${APP_NAME}</title>
        <link>https://github.com/${GITHUB_REPO}</link>
        <description>${APP_NAME} update feed</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
            ${DESCRIPTION_BLOCK}
            <enclosure url="${DOWNLOAD_URL}"
                       type="application/octet-stream"
                       sparkle:edSignature="${ED_SIGNATURE}"
                       length="${ZIP_SIZE}"/>
        </item>
    </channel>
</rss>
APPCAST_EOF

info "appcast.xml updated"

# --- Step 9: GitHub Release ---
step 9 "GitHub Release + push"

git add "$PLIST" "$APPCAST" "$NOTES_FILE" 2>/dev/null || git add "$PLIST" "$APPCAST"
git commit -m "Release v${VERSION} (build ${BUILD_NUMBER})"
git push

# Build the GitHub release body from the same HTML notes (converted to Markdown),
# so the release page shows the human-readable changelog — not just the auto link.
GH_NOTES_FILE="$(mktemp)"
if [[ -f "$NOTES_FILE" ]]; then
    perl -0pe 's{<style.*?</style>}{}gs; s{<h3>(.*?)</h3>}{\n## $1\n}gs; s{<li>(.*?)</li>}{- $1\n}gs; s{</?ul>}{}gs; s{<b>(.*?)</b>}{**$1**}gs; s{<[^>]+>}{}gs; s{&amp;}{&}g; s{&lt;}{<}g; s{&gt;}{>}g; s{^[ \t]+}{}mg' "$NOTES_FILE" | cat -s > "$GH_NOTES_FILE"
else
    echo "Version ${VERSION}" > "$GH_NOTES_FILE"
fi
# Append a Full Changelog link against the previous (currently-latest) release.
PREV_TAG="$(gh release view --json tagName -q .tagName 2>/dev/null || true)"
if [[ -n "$PREV_TAG" ]]; then
    printf '\n\n**Full Changelog**: https://github.com/%s/compare/%s...%s\n' "$GITHUB_REPO" "$PREV_TAG" "$TAG" >> "$GH_NOTES_FILE"
fi

gh release create "$TAG" "$ZIP_NAME" \
    --title "${APP_NAME} v${VERSION}" \
    --notes-file "$GH_NOTES_FILE"
rm -f "$GH_NOTES_FILE"

info "GitHub release $TAG created"

# --- Step 10: Update Homebrew cask ---
step 10 "Update Homebrew cask"

SHA256=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
info "SHA-256: ${SHA256}"

if [[ -f "$HOMEBREW_TAP_CASK" ]]; then
    sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$HOMEBREW_TAP_CASK"
    sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$HOMEBREW_TAP_CASK"

    TAP_DIR=$(dirname "$HOMEBREW_TAP_CASK")
    git -C "$TAP_DIR" add stockdock.rb
    git -C "$TAP_DIR" commit -m "stockdock ${VERSION}"
    git -C "$TAP_DIR" push

    info "Homebrew cask updated and pushed"
else
    warn "Cask file not found at $HOMEBREW_TAP_CASK"
    echo "  Update manually: version \"${VERSION}\", sha256 \"${SHA256}\""
fi

# --- Done ---
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ${APP_NAME} v${VERSION} released successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  GitHub:   https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
echo "  Homebrew: brew install --cask simonsruggi/tap/stockdock"
echo ""

rm -f "$ZIP_NAME"
info "Cleaned up $ZIP_NAME"
