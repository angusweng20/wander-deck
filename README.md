# 漫遊簡報 Wander Deck

**把一資料夾的照片，變成可以上台、想跳哪就跳哪的簡報。**

一般簡報是一頁接一頁往下翻。漫遊簡報是「非線性」的：主畫面擺著幾個主題，
講到哪、觀眾問到哪，就點哪個主題；點照片會放大，還有放大鏡看細節。
適合旅行分享會、品牌故事、作品集、活動回顧。

[English](README.en.md)

## 特色

- 📁 **一個資料夾＝一個主題**：照片丟進去就好，不用排版。HEIC、JPG、MOV 都能直接用。
- 🔀 **非線性**：開場幾頁照順序翻，之後自由跳。
- 🔍 **點照片放大、放大鏡**：滾輪調倍率。
- 🖼️ **展示牆**：照片少的主題，大大的並排展示。
- 🎵 **背景音樂**：循環播放，換頁不中斷，播影片時自動暫停。
- 🎞️ **開場動畫**：插畫裡的吊燈會擺、駱駝會走、樹葉會飄，標題像旗子一樣飄。
- 📱 **結尾 QR code 頁**：放你的 IG 或網站。
- 🔒 **隱私**：產生出來的圖片會自動清掉 GPS 位置和拍攝資訊，原始照片不會被改。
- ✈️ **完全離線**：整個資料夾複製給別人，點兩下就能看。

## 這是給 AI 用的工具

漫遊簡報設計成**由你的 AI 助理操作**：你告訴 AI 照片在哪、想要什麼樣子，
它會照 [`skills/wander-deck/SKILL.md`](skills/wander-deck/SKILL.md) 裡的流程幫你做好，
你只要看成品、說哪裡要改。

### 用 Claude Code

```bash
git clone https://github.com/angusweng20/wander-deck.git ~/wander-deck
mkdir -p ~/.claude/skills && ln -s ~/wander-deck/skills/wander-deck ~/.claude/skills/wander-deck
```
然後跟 Claude 說：「用漫遊簡報，把 ~/Pictures/京都 做成一份分享會簡報」。

### 用其他 AI 工具（Codex、Cursor…）

把這個專案下載下來，跟 AI 說：「請先讀 wander-deck/AGENTS.md，再幫我做一份漫遊簡報」。

## 需求

- macOS（用到 Mac 內建的 `sips` 處理照片）
- Google Chrome（上台時全螢幕＋音樂自動播放；只是看的話任何瀏覽器都行）
- 選用：`ffmpeg`（影片封面）、OpenCV（做開場動畫時 AI 會自動安裝在 `~/.wander-deck`）

## 自己動手（不透過 AI）

```bash
~/wander-deck/scripts/new_deck.sh ~/Desktop/我的簡報 "我的旅行分享會"
```
把照片按主題放進 `~/Desktop/我的簡報/` 底下的子資料夾，點兩下 `更新簡報.command`，
再點兩下 `打開簡報.command`。設定都在 `deck.json`，說明見 [docs/deck-json.md](docs/deck-json.md)。

## 專案結構

```
engine/        簡報本體（deck.html、build.py、兩個 .command）
scripts/       new_deck.sh 建立／升級簡報、preview.sh 截圖檢查、scene_tool.py 拆開場動畫圖層
skills/        給 AI 的操作手冊
docs/          deck.json 設定說明
```

## 授權

程式碼以 [MIT](LICENSE) 授權。你用它做出來的簡報、你的照片和素材，都是你自己的。
