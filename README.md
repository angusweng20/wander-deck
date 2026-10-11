# 漫遊簡報 Wander Deck

**把一趟旅行的照片，變成可以上台、想跳哪就跳哪的簡報。**

挑照片 → 選怎麼分（地點、日期、自己分、AI 分）→ 按「開始製作」，就完成了。
做出來的簡報是一個資料夾，整個複製給別人，點兩下就能看，不用網路。

[English](README.en.md)

## 特色

- 📍 **自動分類**：讀照片的拍攝地點和時間，分成「國家 → 城市」或「一天一個主題」。沒有位置的照片，用前後拍的照片推回去。
- ✨ **AI 小幫手**：用你自己的 ChatGPT Plus／Pro 訂閱登入，AI 看照片幫主題取名、寫標題，或照你給的主題分照片。不另外收費。
- 🎨 **風格包**：內建「水彩旅行」「浮世繪」「經典相紙」。在日本拍的照片會自動用浮世繪。風格包格式公開，誰都能做、能分享。
- 🔀 **非線性**：開場幾頁照順序翻，之後想點哪個主題就點哪個；點照片放大，有放大鏡。
- 🎞️ **開場動畫**：燈籠會擺、熱氣球會飄、樹葉隨風動，標題像旗子一樣飄。
- 🍎 **蘋果生態優先**：直接從「照片」App 挑；HEIC、Live Photo、影片都能用。
- 🔒 **隱私**：產生的圖片自動清掉 GPS 和拍攝資訊；給 AI 看的是縮小、清過的縮圖。原始照片不會被修改。

## 安裝

需要 macOS 14（Sonoma）以上。

### 方法一：一行安裝（推薦）

打開「終端機」，貼上這行，按 Enter：

```bash
curl -fsSL https://raw.githubusercontent.com/angusweng20/wander-deck/main/scripts/install.sh | bash
```

它會自動挑對你的 Mac（Apple 晶片或 Intel）的版本、核對檔案、裝進「應用程式」資料夾，然後打開。

### 方法二：自己下載

到 [Releases](https://github.com/angusweng20/wander-deck/releases/latest) 下載
`Wander-Deck-…-AppleSilicon.zip`（M1 之後的 Mac）或 `…-Intel.zip`，解壓縮後把「Wander Deck」拖進「應用程式」。

**第一次打開會被 Mac 擋下來**，這是正常的——漫遊簡報是免費的開源軟體，沒有付錢給 Apple 做簽章。放行方法：

1. 點兩下打開，看到「無法打開」的訊息，按「完成」。
2. 打開「系統設定 → 隱私權與安全性」，往下捲。
3. 找到「已阻擋 Wander Deck…」，按「**仍要打開**」，輸入電腦密碼。
4. 再打開一次，按「打開」。之後就不會再問了。

（如果 App 裡顯示「Mac 擋住了 AI 小幫手（pi）」，用同樣的方法在「隱私權與安全性」放行 pi。）

## 怎麼用

1. **登入**（可以跳過）：按「用 ChatGPT 登入」，在瀏覽器登入 ChatGPT 帳號。電腦上已經用 [Pi](https://pi.dev) 登入過的話會自動沿用。
2. **挑照片**：從「照片」App 挑，或把照片、資料夾拖進來。
3. **分類**：依地點、依日期、自己分，或讓 AI 分。左邊是主題，可以改名；把照片拖到別的主題就能搬。
4. **設定**：標題、副標（可以讓 AI 寫）、風格、背景音樂、結尾 QR code。
5. **開始製作**：做好按「打開簡報」，全螢幕、音樂自動播放，直接上台。

簡報預設放在「文件／漫遊簡報」。之後要加照片：放進簡報資料夾裡的主題資料夾，點兩下「更新簡報.command」。

## 風格包

風格包是一個資料夾（或打包好的 `.wdstyle` 檔），決定簡報的配色、字型、背景和開場動畫。
在 App 的「設定 → 風格包」可以匯入、匯出。自己做一個：看 [docs/style-pack.md](docs/style-pack.md)。

## 給 AI 用

除了 App，漫遊簡報也能由 AI 助理操作（可以做更細的客製，例如把你自己的插畫做成開場動畫）：

- **Claude Code**：`ln -s ~/wander-deck/skills/wander-deck ~/.claude/skills/wander-deck`，然後說「用漫遊簡報，把 ~/Pictures/京都 做成一份分享會簡報」。
- **其他 AI 工具**：請它先讀 [AGENTS.md](AGENTS.md)。

## 開發

```
app/        Mac App（SwiftUI）和命令列工具 wander（Swift Package）
engine/     簡報本體：deck.html、build.py（Python 版產生器）、兩個 .command
styles/     內建風格包
scripts/    package_app.sh 打包、install.sh 安裝、test.sh 測試、style_pack.py 風格包工具、
            new_deck.sh 建立簡報、preview.sh 截圖、scene_tool.py 拆開場動畫圖層
skills/     給 AI 的操作手冊
docs/       deck.json 設定、風格包格式
examples/   範例簡報「漫遊東海道」（素材全是公眾領域）
```

```bash
scripts/test.sh              # 跑全部測試
scripts/package_app.sh       # 打包成 dist/Wander-Deck-<版本>-AppleSilicon.zip、-Intel.zip
scripts/install.sh --local dist/Wander-Deck-<版本>-AppleSilicon.zip   # 裝到這台 Mac
```

需要 Xcode 16 以上（Swift 6）。Python 版 `engine/build.py` 和 Swift 版 `DeckBuilder` 要產出一樣的結果，測試會比對。

## 授權

程式碼：[MIT](LICENSE)。內建風格包：CC BY 4.0（出處見各包的 `CREDITS.md`）。
App 內附 [Pi](https://github.com/earendil-works/pi)（MIT）。你用它做出來的簡報、你的照片和素材，都是你自己的。
