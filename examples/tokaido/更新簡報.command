#!/bin/bash
# 漫遊簡報：加了照片、改了 deck.json 之後，點兩下這個檔案。
cd "$(dirname "$0")"
echo "正在更新簡報，請稍等⋯"
/usr/bin/python3 _wander/build.py
echo ""
echo "好了，可以關掉這個視窗，回到簡報按 ⌘R 重新整理。"
