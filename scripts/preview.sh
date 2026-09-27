#!/bin/bash
# 給 AI 檢查畫面用：用無頭 Chrome 截一張簡報的圖。
#   scripts/preview.sh <簡報資料夾> [畫面] [輸出.png] [寬x高] [--freeze 秒數]
#   畫面：""＝開場第 1 頁、"#intro/2"、"#/"＝主畫面、"#/主題名"、"#outro"
#   --freeze 秒數：把所有 CSS 動畫停在第幾秒（看動畫某一刻的樣子）
# 注意：截圖只看得到某一瞬間；動畫的速度、幅度要請使用者用眼睛看。
set -e
DECK="$1"; HASH="${2:-}"; OUT="${3:-/tmp/wander-preview.png}"; SIZE="${4:-1920x1080}"
FREEZE=""; [ "$5" = "--freeze" ] && FREEZE="$6"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "需要 Google Chrome"; exit 1; }
cd "$DECK"
PAGE="簡報.html"
if [ -n "$FREEZE" ]; then
  PAGE=".preview.html"
  sed "s#</style>#* { animation-play-state: paused !important; animation-delay: -${FREEZE}s !important; }</style>#" 簡報.html > "$PAGE"
fi
HASH_ENC=$(python3 -c "import sys,urllib.parse;h=sys.argv[1];print(urllib.parse.quote(h,safe='#/'))" "$HASH")
"$CHROME" --headless=new --hide-scrollbars --autoplay-policy=no-user-gesture-required \
  --window-size="${SIZE/x/,}" --virtual-time-budget=4000 \
  --screenshot="$OUT" "file://$(pwd)/$PAGE$HASH_ENC" 2>/dev/null
[ -n "$FREEZE" ] && rm -f "$PAGE"
echo "$OUT"
