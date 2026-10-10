#!/bin/bash
# 安裝漫遊簡報 Wander Deck。
#
# 一行安裝（從 GitHub 下載最新版）：
#   curl -fsSL https://raw.githubusercontent.com/angusweng20/wander-deck/main/scripts/install.sh | bash
# 安裝自己打包的壓縮檔：
#   scripts/install.sh --local dist/Wander-Deck-<版本>-AppleSilicon.zip
#
# 會做的事：下載（並核對 SHA256）→ 解壓縮 → 放進「應用程式」資料夾 → 打開。
# 舊版本會先移到垃圾桶，不會直接刪除。
set -euo pipefail
REPO="angusweng20/wander-deck"
APPNAME="Wander Deck.app"
LABEL="AppleSilicon"; [ "$(uname -m)" = "x86_64" ] && LABEL="Intel"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

if [ "${1:-}" = "--local" ]; then
  ZIP="${2:?請給壓縮檔路徑}"
else
  echo "查詢最新版本⋯"
  API="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")"
  URL="$(printf '%s' "$API" | grep -o "https://[^\"]*Wander-Deck-[^\"]*-${LABEL}\.zip" | head -1)"
  SUMS="$(printf '%s' "$API" | grep -o 'https://[^"]*SHA256SUMS[^"]*\.txt' | head -1)"
  [ -n "$URL" ] || { echo "找不到 ${LABEL} 版的下載檔。"; exit 1; }
  ZIP="$TMP/$(basename "$URL")"
  echo "下載 $(basename "$URL")⋯"
  curl -fL --progress-bar -o "$ZIP" "$URL"
  if [ -n "$SUMS" ]; then
    curl -fsSL -o "$TMP/sums.txt" "$SUMS"
    WANT="$(grep " $(basename "$URL")\$" "$TMP/sums.txt" | awk '{print $1}')"
    GOT="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    [ "$WANT" = "$GOT" ] || { echo "❌ 下載的檔案核對不符，停止安裝。"; exit 1; }
    echo "檔案核對 OK"
  fi
fi

ditto -x -k "$ZIP" "$TMP/unzipped"
[ -d "$TMP/unzipped/$APPNAME" ] || { echo "壓縮檔裡找不到 $APPNAME"; exit 1; }

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
if [ -d "$DEST/$APPNAME" ]; then
  osascript -e "tell application \"Wander Deck\" to quit" >/dev/null 2>&1 || true
  mv "$DEST/$APPNAME" "$HOME/.Trash/Wander Deck (old $(date +%Y%m%d-%H%M%S)).app"
  echo "舊版本已移到垃圾桶。"
fi
mv "$TMP/unzipped/$APPNAME" "$DEST/"
echo "✅ 已安裝到 $DEST/$APPNAME"
open "$DEST/$APPNAME"
