#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
SCHEME="StockDock"
APP_NAME="StockDock"
BUNDLE_ID="com.simone.stockdock"
SIGNING_IDENTITY="Developer ID Application: Simone Ruggiero (M6TP9DBCVL)"
ENTITLEMENTS="StockDock.entitlements"
NOTARY_PROFILE="notarytool"
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

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_PATH/Contents/MacOS/${APP_NAME}"

info "App bundle assembled: $APP_PATH"

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

xcrun notarytool submit "$ZIP_NAME" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

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

git add "$PLIST" "$APPCAST"
git commit -m "Release v${VERSION} (build ${BUILD_NUMBER})"
git push

gh release create "$TAG" "$ZIP_NAME" \
    --title "${APP_NAME} v${VERSION}" \
    --generate-notes

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
