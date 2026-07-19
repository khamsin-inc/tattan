#!/usr/bin/env bash
# Notarization の認証情報を macOS キーチェーンに保存する初回セットアップ。
# 1 度だけ動かせば、release.sh からは --keychain-profile tattan-notary で
# 自動的に参照される。Apple ID + Team ID + アプリ用パスワードはこの
# キーチェーン項目にのみ保存され、git には絶対に出ない。
#
# 前提:
#   1. Apple Developer Program に加入済み（Developer ID 証明書を持っている）
#   2. アプリ用パスワード（App-Specific Password）を発行済み
#      https://appleid.apple.com → サインインとセキュリティ → アプリ用パスワード
#      ※ 発行時に 1 回しか表示されないので 1Password 等に保存しておくこと
#
# 使い方: bash scripts/setup-notarytool.sh

set -euo pipefail

PROFILE="tattan-notary"
APPLE_ID_DEFAULT="ken@khamsin.jp"
TEAM_ID_DEFAULT="4H6H6NFG9L"

echo "▸ notarytool キーチェーンプロファイル「${PROFILE}」を作成します"
echo

read -rp "Apple ID [${APPLE_ID_DEFAULT}]: " APPLE_ID
APPLE_ID="${APPLE_ID:-$APPLE_ID_DEFAULT}"

read -rp "Team ID [${TEAM_ID_DEFAULT}]: " TEAM_ID
TEAM_ID="${TEAM_ID:-$TEAM_ID_DEFAULT}"

echo
echo "アプリ用パスワード（16 文字 + ハイフン）を入力してください。"
echo "入力は画面に表示されません。"
read -rsp "App-Specific Password: " APP_PWD
echo

xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PWD"

echo
echo "✅ 保存完了。確認:"
xcrun notarytool history --keychain-profile "$PROFILE" 2>&1 | head -5 || true
echo
echo "これで release.sh を流せます。"
