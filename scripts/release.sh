#!/usr/bin/env bash
# Tattan のローカル配布ビルド: Release を Developer ID で署名 → 公証 → staple → .dmg 化。
#
# 前提（初回のみ・各 1 回）:
#   1. Developer ID Application 証明書がキーチェーンにある（team 4H6H6NFG9L）
#      Xcode > Settings > Accounts > 該当 Apple ID > Manage Certificates > + > Developer ID Application
#   2. notarytool の認証情報をキーチェーンに保存済み（プロファイル名 "tattan-notary"）:
#      xcrun notarytool store-credentials tattan-notary \
#        --apple-id <Apple ID メール> --team-id 4H6H6NFG9L --password <App 用パスワード>
#
# 使い方: bash scripts/release.sh
set -euo pipefail

SCHEME="Tattan"
CONFIG="Release"
TEAM_ID="4H6H6NFG9L"
NOTARY_PROFILE="tattan-notary"

# バージョンは project.yml の MARKETING_VERSION から拾う
VERSION=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' project.yml)

BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/Tattan.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Tattan.app"
ZIP="$BUILD_DIR/Tattan-notarize.zip"
DMG="$BUILD_DIR/Tattan-${VERSION}.dmg"
BG_PNG="scripts/release-assets/dmg-background.png"

# 前提ツールチェック
require() { command -v "$1" >/dev/null || { echo "❌ $1 not found. $2"; exit 1; } }
require create-dmg "Install: brew install create-dmg"
[ -f "$BG_PNG" ] || { echo "❌ DMG background not found: $BG_PNG"; exit 1; }

# 既存の成果物はゴミ箱へ退避（破壊的削除はしない方針）
if [ -d "$BUILD_DIR" ]; then
    mkdir -p "$HOME/claude-trash"
    mv "$BUILD_DIR" "$HOME/claude-trash/tattan-release-$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$BUILD_DIR"

echo "▸ [1/6] Archiving ($CONFIG, Developer ID)…"
xcodebuild archive \
    -project Tattan.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID"

echo "▸ [2/6] Exporting with Developer ID…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -allowProvisioningUpdates

echo "▸ [3/6] Notarizing the app (uploads to Apple; a few minutes)…"
# 公証はアプリのコードに対して行うので、まず .app だけを zip して送る
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ [4/6] Stapling the notarization ticket onto the app…"
# staple しておけばオフラインでも Gatekeeper を通過できる
xcrun stapler staple "$APP"

echo "▸ [5/6] Packaging the stapled app into a DMG (with arrow layout)…"
# create-dmg は背景画像 + アイコン配置 + Applications シンボリックリンクを 1 コマンドで仕込む。
# 配置座標は scripts/release-assets/dmg-background.svg のコメントと一致させること
create-dmg \
    --volname "Tattan ${VERSION}" \
    --background "$BG_PNG" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 120 \
    --icon "Tattan.app" 165 200 \
    --hide-extension "Tattan.app" \
    --app-drop-link 495 200 \
    --no-internet-enable \
    "$DMG" \
    "$APP"

echo "▸ [6/7] Notarizing & stapling the DMG itself (so the download opens cleanly)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ [7/7] Generating appcast.xml entry for Sparkle (G-4)…"
# sign_update は Sparkle SPM artifact の中にある。Xcode で一度以上 Tattan をビルドしてないと存在しない
SIGN_UPDATE=$(find "$HOME/Library/Developer/Xcode/DerivedData/Tattan-"*/SourcePackages/artifacts/sparkle/Sparkle/bin -name sign_update 2>/dev/null | head -1)
[ -x "$SIGN_UPDATE" ] || { echo "❌ sign_update not found. Build Tattan in Xcode first so Sparkle SPM artifacts get fetched."; exit 1; }

# sign_update の出力例:  sparkle:edSignature="..." length="..."
SIGN_OUT=$("$SIGN_UPDATE" "$DMG")
ED_SIG=$(echo "$SIGN_OUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGN_OUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$ED_SIG" ] || { echo "❌ Failed to parse edSignature from: $SIGN_OUT"; exit 1; }
[ -n "$LENGTH" ] || { echo "❌ Failed to parse length from: $SIGN_OUT"; exit 1; }

PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
APPCAST="$BUILD_DIR/appcast.xml"
sed \
  -e "s|__VERSION__|${VERSION}|g" \
  -e "s|__BUILD__|${BUILD}|g" \
  -e "s|__PUB_DATE__|${PUB_DATE}|g" \
  -e "s|__ED_SIGNATURE__|${ED_SIG}|g" \
  -e "s|__LENGTH__|${LENGTH}|g" \
  scripts/appcast-template.xml > "$APPCAST"

echo
echo "✅ Done."
echo "   App:     $APP"
echo "   DMG:     $DMG"
echo "   Appcast: $APPCAST"
echo
echo "Gatekeeper check:"
spctl --assess --type execute --verbose "$APP" || true
echo
echo "Next steps:"
echo "  1. Upload $DMG as the v${VERSION} GitHub Release asset:"
echo "       gh release create v${VERSION} \"$DMG\" --title \"Tattan ${VERSION}\" --notes …"
echo "  2. Upload $APPCAST to your appcast host (SUFeedURL target in Info.plist)"
