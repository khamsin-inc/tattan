#!/usr/bin/env bash
# DMG 背景画像を SVG から PNG (@1x + @2x) に書き出す。
# release.sh はラスタライズ済み PNG を使うので、このスクリプトは
# 背景デザインを編集したときだけ実行する。
#
# 必要なツール: rsvg-convert（`brew install librsvg`）

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v rsvg-convert >/dev/null; then
    echo "❌ rsvg-convert not found. Install: brew install librsvg"
    exit 1
fi

rsvg-convert -w 660  -h 400  dmg-background.svg -o dmg-background.png
rsvg-convert -w 1320 -h 800  dmg-background.svg -o dmg-background@2x.png

echo "✅ Rendered:"
echo "   - dmg-background.png    (660×400)"
echo "   - dmg-background@2x.png (1320×800)"
