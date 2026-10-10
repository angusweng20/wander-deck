#!/bin/bash
# 漫遊簡報：加了照片、改了 deck.json 之後，點兩下這個檔案。
# 有裝「Wander Deck」App 就用 App 內建的工具；沒有就用 Mac 的 Python。
cd "$(dirname "$0")"
echo "正在更新簡報，請稍等⋯"
CLI=""
for APP in "/Applications/Wander Deck.app" "$HOME/Applications/Wander Deck.app"; do
  [ -x "$APP/Contents/MacOS/wander" ] && { CLI="$APP/Contents/MacOS/wander"; break; }
done
if [ -n "$CLI" ]; then
  "$CLI" build .
elif xcode-select -p >/dev/null 2>&1; then
  /usr/bin/python3 _wander/build.py
else
  echo "找不到更新工具。請先安裝 Wander Deck App（或 Xcode 命令列工具）。"
  exit 1
fi
echo ""
echo "好了，可以關掉這個視窗，回到簡報按 ⌘R 重新整理。"
