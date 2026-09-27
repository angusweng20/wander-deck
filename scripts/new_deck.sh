#!/bin/bash
# 建立一份新的漫遊簡報，或把既有簡報的程式升級到最新版。
#   scripts/new_deck.sh <簡報資料夾> [標題]
#   scripts/new_deck.sh --upgrade <簡報資料夾>
# 只會新增／更新程式檔（簡報.html、_wander/build.py、兩個 .command），
# 不會動照片、deck.json、_assets。
set -e
ENGINE="$(cd "$(dirname "$0")/../engine" && pwd)"
UPGRADE=0
[ "$1" = "--upgrade" ] && { UPGRADE=1; shift; }
DECK="$1"; TITLE="${2:-漫遊簡報}"
[ -z "$DECK" ] && { echo "用法：$0 [--upgrade] <簡報資料夾> [標題]"; exit 1; }
if [ "$UPGRADE" = 1 ] && [ ! -f "$DECK/_wander/build.py" ]; then
  echo "「$DECK」不是漫遊簡報資料夾（沒有 _wander/build.py）"; exit 1
fi
mkdir -p "$DECK/_wander" "$DECK/_assets"
cp "$ENGINE/deck.html" "$DECK/簡報.html"
cp "$ENGINE/build.py" "$DECK/_wander/build.py"
cp "$ENGINE/launchers/"*.command "$DECK/"
chmod +x "$DECK/"*.command
if [ ! -f "$DECK/deck.json" ]; then
  python3 - "$DECK/deck.json" "$TITLE" <<'PY'
import json, sys
json.dump({
  "title": sys.argv[2],
  "subtitle": "點一個主題，想從哪裡開始都可以",
  "background": None,
  "logo": None,
  "music": {"file": None, "volume": 50},
  "topics": {"order": [], "hidden": [], "walls": [], "labels": {}},
  "intro": [],
  "scenes": {},
  "outro": None
}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
fi
echo "$([ $UPGRADE = 1 ] && echo 已升級 || echo 已建立)：$DECK"
