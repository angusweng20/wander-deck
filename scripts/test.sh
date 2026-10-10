#!/bin/bash
# 跑全部檢查：Swift 自動測試（含跟 Python 版 build.py 比對）＋風格包格式檢查。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for s in "$ROOT"/styles/*/; do python3 "$ROOT/scripts/style_pack.py" check "$s"; done
python3 -m py_compile "$ROOT/engine/build.py" "$ROOT/scripts/style_pack.py" "$ROOT/scripts/scene_tool.py"
cd "$ROOT/app" && swift test --scratch-path "${TMPDIR:-/tmp}/wanderdeck-build" 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -5
