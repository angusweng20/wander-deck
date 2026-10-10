#!/bin/bash
# 建立一份新的漫遊簡報，或把既有簡報的程式升級到最新版。
#   scripts/new_deck.sh [--style <風格id>] <簡報資料夾> [標題]
#   scripts/new_deck.sh --upgrade [--style <風格id>] <簡報資料夾>
# 只會新增／更新程式檔（簡報.html、_wander/build.py、兩個 .command）和 _style/，
# 不會動照片、_assets。deck.json 只在第一次建立、或指定 --style 時寫入 "style" 一欄。
# 風格 id 見 styles/（watercolor 水彩、ukiyoe 浮世繪、classic 經典相紙）。
set -e
WD="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$WD/engine"
UPGRADE=0; STYLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --upgrade) UPGRADE=1; shift ;;
    --style) STYLE="$2"; shift 2 ;;
    *) break ;;
  esac
done
DECK="$1"; TITLE="${2:-漫遊簡報}"
[ -z "$DECK" ] && { echo "用法：$0 [--upgrade] [--style 風格id] <簡報資料夾> [標題]"; exit 1; }
if [ "$UPGRADE" = 1 ] && [ ! -f "$DECK/_wander/build.py" ]; then
  echo "「$DECK」不是漫遊簡報資料夾（沒有 _wander/build.py）"; exit 1
fi
if [ -n "$STYLE" ] && [ ! -f "$WD/styles/$STYLE/style.json" ]; then
  echo "找不到風格「$STYLE」。可以用的有：$(ls "$WD/styles" | tr '\n' ' ')"; exit 1
fi
mkdir -p "$DECK/_wander" "$DECK/_assets"
HTML="$(ls -1 "$DECK"/*.html 2>/dev/null | head -1)"
cp "$ENGINE/deck.html" "${HTML:-$DECK/簡報.html}"
cp "$ENGINE/build.py" "$DECK/_wander/build.py"
OPEN="$(ls -1 "$DECK"/*.command 2>/dev/null | grep -E '打開|Open' | head -1)"
UPDATE="$(ls -1 "$DECK"/*.command 2>/dev/null | grep -E '更新|Update' | head -1)"
cp "$ENGINE/launchers/打開簡報.command" "${OPEN:-$DECK/打開簡報.command}"
cp "$ENGINE/launchers/更新簡報.command" "${UPDATE:-$DECK/更新簡報.command}"
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
  "outro": None
}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
fi
if [ -n "$STYLE" ]; then
  python3 "$WD/scripts/style_pack.py" install "$WD/styles/$STYLE" "$DECK" >/dev/null
  echo "風格：$STYLE"
elif [ "$UPGRADE" = 1 ] && [ -f "$DECK/_style/style.json" ]; then
  # 升級時順便更新內建風格包（id 一樣才換）
  ID="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['id'])" "$DECK/_style/style.json")"
  [ -f "$WD/styles/$ID/style.json" ] && python3 "$WD/scripts/style_pack.py" install "$WD/styles/$ID" "$DECK" >/dev/null && echo "風格已更新：$ID"
fi
echo "$([ $UPGRADE = 1 ] && echo 已升級 || echo 已建立)：$DECK"
