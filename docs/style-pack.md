# 風格包格式 `wander-style/1`

風格包決定一份漫遊簡報「長什麼樣子」：配色、字型、背景紙紋、開場動畫、相框。
照片和主題是使用者的；風格包是可以分享、可以替換的外觀。

任何人都可以做風格包。做好後打包成一個 `.wdstyle` 檔，別人在 App 的「設定 → 風格包 → 匯入」就能用。

## 資料夾長這樣

```
kyoto-watercolor/
  style.json        ← 必要：所有設定
  CREDITS.md        ← 必要：每個素材的出處和授權
  preview.jpg       ← 建議：App 裡挑風格時顯示的預覽圖（16:9）
  paper.jpg         ← 主畫面、主題頁的背景
  style.css         ← 選用：額外的樣式
  scene/            ← 開場動畫的背景和會動的圖層
    bg.jpg
    lantern.png
```

## style.json

```jsonc
{
  "format": "wander-style/1",              // 固定寫這個
  "id": "kyoto-watercolor",                 // 小寫英文、數字、-，2–40 字；同 id 會被當成同一個風格
  "name": { "zh-Hant": "京都水彩", "en": "Kyoto Watercolor" },   // 也可以只寫一個字串
  "version": "1.0.0",                       // 改版就把數字加大
  "author": "你的名字",
  "license": "CC-BY-4.0",                   // CC-BY-4.0（建議）、CC-BY-SA-4.0、CC0-1.0 三選一
  "description": { "zh-Hant": "⋯", "en": "⋯" },
  "countries": ["JP"],                      // 適合哪些國家（ISO 代碼）。App 依照片 GPS 自動挑；[] = 不限
  "preview": "preview.jpg",
  "credits": "CREDITS.md",

  "theme": {                                // 跟 deck.json 的 theme 一樣，另外可以換字型
    "paper": "#f6f2ea", "ink": "#3d4b5c", "inkSoft": "#76828f", "card": "#fffdf9",
    "serif": "\"Songti TC\", serif",        // 標題用的字型（CSS font-family）
    "sans": "\"PingFang TC\", sans-serif"
  },
  "background": "paper.jpg",
  "css": "style.css",
  "music": { "file": "music.mp3", "volume": 50 },   // 選用：使用者沒有自己挑音樂時用這首

  "scenes": {                               // 跟 deck.json 的 scenes 一樣，路徑相對於風格包
    "main": {
      "background": "scene/bg.jpg",
      "layers": [
        { "src": "scene/lantern.png", "box": [159, 211, 111], "effect": "swing", "amount": 1.8, "speed": 4.2, "origin": "50% 0" }
      ]
    }
  },

  "intro": [                                // 開場頁的「版型」：標題、副標、拍立得會自動填進去
    {
      "type": "scene", "scene": "main",
      "title": { "text": "{title}", "at": [50, 9, 44], "maxHeight": 13, "align": "center", "effect": "flag",
                 "font": "600 {size}px \"Songti TC\", serif", "color": "#3d4b5c", "glow": "rgba(255,255,255,.9)" },
      "texts": [ { "text": "{subtitle}", "at": [50, 24.5, 44], "size": 1.3, "align": "center" } ],
      "cards": "auto",
      "cardSlots": [ { "at": [57, 40, 14], "rot": -5 }, { "at": [73, 45, 13], "rot": 4 } ]
    }
  ]
}
```

### 開場頁的版型欄位

| 欄位 | 意思 |
|---|---|
| `title.text` | 標題文字。`{title}`、`{subtitle}` 會換成簡報的標題、副標。瀏覽器會把字畫成圖，所以一樣能像旗子飄 |
| `title.at` | `[左%, 上%, 最寬%]`，相對畫面 |
| `title.maxHeight` | 標題最高佔畫面高度幾 %（字少時不會變得超大），預設 18 |
| `title.align` | 在「最寬」範圍裡靠 `left`／`center`／`right` |
| `title.font` | CSS 字型寫法，`{size}` 會被換成數字 |
| `title.color`、`title.glow` | 字的顏色、外光暈（深色背景上加淡色光暈比較好讀） |
| `title.spacing` | 字距，例如 `"6px"` |
| `texts` | 其他文字（例如副標）：`text`、`at`、`size`（畫面寬度的 %）、`align`、`color`、`font` |
| `cards: "auto"` | 從前幾個主題各拿一張照片當拍立得，下面寫主題名稱 |
| `cardSlots` | 拍立得擺在哪：`at`、`rot`，數量決定最多放幾張 |

`layers` 的 `effect`：`swing` 鐘擺、`walk` 行走、`float` 漂浮、`breeze`／`breeze-soft` 微風、`flutter` 旗幟、`none`。
做法見 [`skills/wander-deck/SKILL.md`](../skills/wander-deck/SKILL.md) 的「開場動畫」。

## 規則（不合格的風格包不能匯入）

- 只收這些檔案：圖片（jpg、png、webp、gif）、`css`、字型（woff、woff2、otf、ttf）、音樂（mp3、m4a、aac）、`json`、`md`、`txt`。
  **不收程式**（`.js`、`.html`⋯），也不能有捷徑（symlink）。
- 路徑都是風格包裡的相對路徑，不能用 `..` 跳出去。
- `style.css` 不能載入網路上的東西（`@import`、`http` 網址）——簡報要能離線看。字型請放進風格包，用相對路徑。
- 整包最多 80MB、400 個檔案。
- 每個素材都要在 `CREDITS.md` 寫清楚出處和授權。用 AI 畫的也要寫。

## 打包、檢查、匯入

```bash
python3 scripts/style_pack.py check  styles/kyoto-watercolor              # 檢查
python3 scripts/style_pack.py export styles/kyoto-watercolor              # 打包成 kyoto-watercolor-1.0.0.wdstyle
python3 scripts/style_pack.py install styles/kyoto-watercolor ~/我的簡報    # 裝進一份簡報（寫進 deck.json 的 "style"）
```

`.wdstyle` 其實就是 zip，最上層是一個以 id 命名的資料夾。App 匯入時會先看清單、只解開白名單裡的檔案，再檢查一次才放進
`~/Library/Application Support/Wander Deck/styles/`。

## 授權

建議用 **CC BY 4.0**：別人可以自由使用、修改、再分享，但要註明原作者。
漫遊簡報內建的三個風格包都用 CC BY 4.0（裡面的公眾領域素材仍是公眾領域）。
