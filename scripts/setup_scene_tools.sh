#!/bin/bash
# 只有要做「開場動畫」（把插畫拆成會動的圖層）才需要。
# 在 ~/.wander-deck/venv 建一個獨立的 Python 環境，裝 OpenCV，不會動到系統。
set -e
VENV="$HOME/.wander-deck/venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q numpy opencv-python-headless
"$VENV/bin/python" -c "import cv2; print('OpenCV', cv2.__version__, '就緒：', '$VENV/bin/python')"
