#!/bin/bash
# 把 Wander Deck 打包成可以發給別人的 Mac App。
#   scripts/package_app.sh [arm64|x86_64|all]     （預設 all：Apple 晶片版＋Intel 版各一份）
# 產出在 dist/：Wander-Deck-<版本>-AppleSilicon.zip、Wander-Deck-<版本>-Intel.zip、SHA256SUMS-<版本>.txt
#
# 會做的事：
#   1. swift build 編譯 App 和命令列工具
#   2. 下載 Pi 的官方單一執行檔版本（核對 SHA256），放進 App 裡，使用者不用另外安裝
#   3. 放進簡報引擎（engine/）和內建風格包（styles/）
#   4. 用「臨時簽章」（ad-hoc，不用 Apple 開發者帳號）簽好
# 不會上傳任何東西；要發佈到 GitHub 由人自己決定。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
PI_VERSION="1.1.0"
ARCHES="${1:-all}"; [ "$ARCHES" = all ] && ARCHES="x86_64 arm64"   # 最後做 arm64，dist/ 留下的 .app 是 Apple 晶片版
DIST="$ROOT/dist"
# 編譯暫存、Pi 下載檔都放在暫存資料夾（專案若在 iCloud 同步的資料夾，不要把大量暫存檔同步上去）
BUILD="${TMPDIR:-/tmp}/wanderdeck-build"; CACHE="${TMPDIR:-/tmp}/wanderdeck-pi-cache"
# 在暫存資料夾組裝和簽章：專案若放在 iCloud 同步的資料夾，系統會一直替檔案加標記，簽章會失敗
STAGE="${TMPDIR:-/tmp}/wanderdeck-package"
mkdir -p "$DIST" "$CACHE" "$STAGE"

fetch_pi() {   # $1 = arm64 | x64
  local tgz="$CACHE/pi-darwin-$1.tar.gz"
  if [ ! -f "$tgz" ]; then
    echo "下載 Pi ${PI_VERSION}（${1}）⋯"
    curl -fsSL -o "$tgz" "https://github.com/earendil-works/pi/releases/download/v$PI_VERSION/pi-darwin-$1.tar.gz"
    curl -fsSL -o "$CACHE/SHA256SUMS" "https://github.com/earendil-works/pi/releases/download/v$PI_VERSION/SHA256SUMS"
  fi
  [ -f "$CACHE/SHA256SUMS" ] || curl -fsSL -o "$CACHE/SHA256SUMS" "https://github.com/earendil-works/pi/releases/download/v$PI_VERSION/SHA256SUMS"
  local want; want="$(grep " pi-darwin-$1.tar.gz" "$CACHE/SHA256SUMS" | awk '{print $1}')"
  local got; got="$(shasum -a 256 "$tgz" | awk '{print $1}')"
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "❌ Pi 下載檔核對不符，停止。"; rm -f "$tgz"; exit 1; }
  if [ ! -f "$CACHE/PI-LICENSE" ]; then
    curl -fsSL -o "$CACHE/PI-LICENSE" "https://raw.githubusercontent.com/earendil-works/pi/v$PI_VERSION/LICENSE" || true
  fi
}

for ARCH in $ARCHES; do
  case "$ARCH" in
    arm64) PIARCH=arm64; LABEL=AppleSilicon ;;
    x86_64) PIARCH=x64; LABEL=Intel ;;
    *) echo "不認得的架構：$ARCH"; exit 1 ;;
  esac
  echo "== 編譯（${ARCH}）"
  (cd "$ROOT/app" && swift build --scratch-path "$BUILD" -c release --arch "$ARCH" --product WanderDeck >/dev/null && \
                     swift build --scratch-path "$BUILD" -c release --arch "$ARCH" --product wander >/dev/null)
  BIN="$(cd "$ROOT/app" && swift build --scratch-path "$BUILD" -c release --arch "$ARCH" --show-bin-path)"
  fetch_pi "$PIARCH"

  APP="$STAGE/Wander Deck.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN/WanderDeck" "$APP/Contents/MacOS/WanderDeck"
  cp "$BIN/wander" "$APP/Contents/MacOS/wander"

  # 簡報引擎和風格包
  rsync -a --exclude ".DS_Store" "$ROOT/engine/" "$APP/Contents/Resources/engine/"
  rsync -a --exclude ".DS_Store" "$ROOT/styles/" "$APP/Contents/Resources/styles/"

  # Pi（單一執行檔版；範例資料夾用不到，拿掉）
  tar -xzf "$CACHE/pi-darwin-$PIARCH.tar.gz" -C "$APP/Contents/Resources"
  rm -rf "$APP/Contents/Resources/pi/examples"
  [ -f "$CACHE/PI-LICENSE" ] && cp "$CACHE/PI-LICENSE" "$APP/Contents/Resources/pi/LICENSE"

  # 圖示、Info.plist、App 名稱的中文
  [ -f "$ROOT/app/Resources/AppIcon.icns" ] && cp "$ROOT/app/Resources/AppIcon.icns" "$APP/Contents/Resources/"
  for L in zh-Hant en; do mkdir -p "$APP/Contents/Resources/$L.lproj"; done
  printf '"CFBundleDisplayName" = "漫遊簡報";\n"CFBundleName" = "漫遊簡報";\n"NSPhotoLibraryUsageDescription" = "漫遊簡報要讀取你挑選的照片，把它們做成簡報。照片不會被修改。";\n' \
    > "$APP/Contents/Resources/zh-Hant.lproj/InfoPlist.strings"
  printf '"CFBundleDisplayName" = "Wander Deck";\n"CFBundleName" = "Wander Deck";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
  cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>WanderDeck</string>
  <key>CFBundleIdentifier</key><string>io.github.angusweng20.wanderdeck</string>
  <key>CFBundleName</key><string>Wander Deck</string>
  <key>CFBundleDisplayName</key><string>Wander Deck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hant</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hant</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPhotoLibraryUsageDescription</key><string>Wander Deck reads the photos you pick to build your presentation. Photos are never changed.</string>
</dict></plist>
PLIST

  # 臨時簽章：先簽裡面的程式（Pi 和它的原生模組），再簽整個 App
  echo "== 簽章（ad-hoc）"
  xattr -cr "$APP"     # 清掉我們自己複製過程留下的 Finder 屬性，不然簽章會失敗
  find "$APP/Contents/Resources" -name "*.node" -exec codesign --force --sign - {} \;
  codesign --force --sign - "$APP/Contents/Resources/pi/pi"
  codesign --force --sign - "$APP/Contents/MacOS/wander"
  codesign --force --sign - "$APP"
  codesign --verify --deep --strict "$APP" && echo "簽章檢查 OK"

  ZIP="$DIST/Wander-Deck-$VERSION-$LABEL.zip"
  rm -f "$ZIP"
  (cd "$STAGE" && ditto -c -k --norsrc --keepParent "Wander Deck.app" "$ZIP")
  echo "✅ ${ZIP}（$(du -h "$ZIP" | awk '{print $1}')）"
done
(cd "$DIST" && shasum -a 256 Wander-Deck-"$VERSION"-*.zip > "SHA256SUMS-$VERSION.txt")
echo "完成。壓縮檔在 dist/；要裝到這台 Mac：scripts/install.sh --local dist/Wander-Deck-${VERSION}-AppleSilicon.zip"
