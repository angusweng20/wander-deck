#!/bin/bash
# 漫遊簡報：用這個打開，全螢幕，背景音樂一打開就會播。
# 會開一個獨立的 Chrome 視窗（允許自動播放），不影響你平常用的 Chrome。
cd "$(dirname "$0")"
HTML="$(ls -1 *.html 2>/dev/null | head -1)"
[ -z "$HTML" ] && { echo "這個資料夾裡找不到簡報的 .html 檔"; exit 1; }
PAGE="file://$(pwd)/$HTML"
if [ -d "/Applications/Google Chrome.app" ]; then
  open -na "Google Chrome" --args \
    --user-data-dir="$HOME/Library/Application Support/WanderDeck-Chrome" \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run --no-default-browser-check \
    --start-fullscreen "$PAGE"
else
  echo "沒有 Google Chrome，改用預設瀏覽器打開（音樂要點一下畫面才會開始）。"
  open "$HTML"
fi
