# deck.json 設定說明

所有路徑都是**相對於簡報資料夾**。改完跑 `python3 _wander/build.py --check` 檢查，
找不到的檔案、寫錯的資料夾名稱都會列出來。

```jsonc
{
  "title": "世界某處分享會",                     // 主畫面大標、瀏覽器分頁名稱
  "subtitle": "點一個主題，想從哪裡開始都可以",   // 主畫面副標，不要就給 ""
  "lang": "zh-Hant-TW",                         // "en" 的話，介面按鈕會變英文
  "style": "watercolor",                        // 風格包（裝在 _style/）。配色、背景、開場都用它的，
                                                // 下面自己寫的設定會蓋過風格包。格式見 docs/style-pack.md
  "background": "_assets/background.jpg",       // 主畫面和主題頁的全螢幕背景
  "logo": "_assets/logo.png",                   // 主畫面標題上方的 LOGO（建議去背 PNG）
  "theme": {                                    // 顏色，全部可省略
    "paper": "#f4ebdc",   // 底色
    "ink": "#4a3a2b",     // 字
    "inkSoft": "#7a6552", // 次要的字
    "card": "#fffdf8"     // 相紙白
  },

  "music": { "file": "_assets/music.mp3", "volume": 50 },   // 循環播放；volume 0–100 是起始音量

  "topics": {
    "order":  ["01 開始", "02 旅途"],            // 主題順序（資料夾名稱）；沒寫到的排最後
    "hidden": ["私人照片"],                      // 不出現在簡報上的資料夾
    "walls":  ["01 開始"],                       // 展示牆：照片一樣高並排放大、不能點（適合 2–4 張）
    "labels": { "02 旅途": "那些路上" }           // 網頁上顯示的名字（資料夾不用改名）
  },

  "intro": [                                    // 開場頁，照順序翻；不要開場就給 []
    { "type": "image", "src": "_assets/intro/1.png" },          // 靜態圖（Keynote／Canva 匯出）
    { "type": "scene", "scene": "main",                          // 動畫頁，用下面 scenes 裡的 main
      "title": { "src": "_assets/title.png", "alt": "標題文字",
                 "at": [20, 32, 60],            // [左%, 上%, 寬%]，相對畫面
                 "effect": "flag",              // "flag" 像旗子飄；"none" 不動
                 "wave": { "period": 4.6, "amp1": 0.011 } },    // 可選：飄動週期（秒）與右端擺幅
      "cards": [                                // 拍立得照片（可選）
        { "photo": "_assets/me.jpg", "at": [4, 22, 26], "rot": -6, "caption": "那年夏天",
          "frame": "_assets/polaroid.png",      // 可選：相框圖（中間要是透明洞）；沒給就用 CSS 畫
          "hole": [14.26, 10.70, 71.48, 64.84]  // 相框洞的位置 [左%, 上%, 寬%, 高%]，照片會塞滿這格
        }
      ] }
  ],

  "scenes": {
    "main": {
      "background": "_assets/scene/bg.png",     // 已經挖掉會動物件、補好背景的插畫
      "layers": [                               // 疊放順序＝陣列順序
        { "src": "_assets/scene/leaves.png",  "box": [0, 0, 492],     "effect": "breeze" },
        { "src": "_assets/scene/lantern.png", "box": [187, 0, 109],   "effect": "swing",
          "amount": 1.1, "speed": 4.4, "origin": "46% 0" },
        { "src": "_assets/scene/flags.png",   "box": [1179, 0, 478],  "effect": "flutter" },
        { "src": "_assets/scene/camels.png",  "box": [583, 784, 251], "effect": "walk",
          "amount": 30, "speed": 16 }
      ]
    }
  },

  "outro": {                                    // 結尾頁：左下角 QR 按鈕進入；不要就給 null
    "qr": "_assets/qr.png",
    "handle": "@your_ig",                       // 寫在拍立得下緣的手寫字
    "heading": "謝謝你來",
    "tagline": "Found somewhere, cherished here.",
    "cta": "掃描追蹤 Instagram",
    "logo": true,                               // 標題上方放 LOGO
    "frame": null, "hole": null                 // 同拍立得，可用相框圖
  },

  "text": {                                     // 介面文字，可選；{n} 會換成數字
    "home": "← Home", "toIntro": "← Intro", "fullscreen": "Fullscreen", "back": "← Back",
    "places": "{n} places", "photos": "{n} photos", "videos": "{n} videos"
  }
}
```

## 用風格包時

`"style"` 有設定、而且 deck.json **沒有寫 `intro`** 時，開場頁直接用風格包的版型：標題、副標自動填入，
拍立得自動放前幾個主題的照片。想自己排開場就照常寫 `intro`；想改回用風格包的開場就寫 `"intro": "style"`。

開場頁的標題也可以不用圖、直接寫字（風格包就是這樣用的）：

```jsonc
"title": { "text": "京都・秋日", "at": [50, 9, 44], "maxHeight": 13, "align": "center",
           "font": "600 {size}px \"Songti TC\", serif", "color": "#3d4b5c", "effect": "flag" },
"texts": [ { "text": "五天四夜", "at": [50, 24, 44], "size": 1.3, "align": "center" } ],
"cards": "auto", "cardSlots": [ { "at": [57, 40, 14], "rot": -5 } ]
```

欄位意思見 [style-pack.md](style-pack.md#開場頁的版型欄位)。

## 圖層 `layers` 欄位

| 欄位 | 意思 |
|---|---|
| `src` | 圖層 PNG（`scene_tool.py cut`／`region` 產生） |
| `box` | `[x, y, 寬]`，**原始背景圖的像素座標**（工具會直接印出來） |
| `effect` | `swing` 鐘擺、`walk` 行走、`float` 漂浮、`breeze` 微風、`breeze-soft` 較輕的微風、`flutter` 旗幟、`none` |
| `speed` | 一個循環幾秒（swing／walk／float） |
| `amount` | swing＝擺動角度；walk＝走多遠（圖層寬度的 %）；float＝上下幾 % |
| `origin` | swing 的支點，例如 `"50% 0"`＝上方中間 |
| `delay` | 起始延遲（秒，可負數），讓幾個東西不要同步 |

`breeze`／`flutter` 的強度和速度寫在 `簡報.html` 的 SVG filter 裡，需要時可以改那邊。

## 開場頁的網址

`簡報.html`＝開場第 1 頁、`#intro/2`＝第 2 頁、`#/`＝主畫面、`#/資料夾名`＝主題、`#outro`＝結尾頁。
