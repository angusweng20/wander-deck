import Foundation

/// 介面文字：繁體中文和英文。預設跟系統語言，設定裡可以換。
public enum L10n {
    public static let languageKey = "WanderDeckLanguage"   // "zh" / "en" / 沒設＝跟系統

    public static var isEnglish: Bool {
        if let pick = UserDefaults.standard.string(forKey: languageKey) { return pick == "en" }
        let pref = Locale.preferredLanguages.first?.lowercased() ?? "zh"
        return !pref.hasPrefix("zh")
    }

    /// 簡報裡 deck.json 的 lang
    public static var deckLang: String { isEnglish ? "en" : "zh-Hant-TW" }
    public static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_Hant_TW") }

    public static func t(_ key: String, _ args: CVarArg...) -> String {
        let table = isEnglish ? en : zh
        let s = table[key] ?? (isEnglish ? uiEn[key] : uiZh[key]) ?? zh[key] ?? uiZh[key] ?? key
        return args.isEmpty ? s : String(format: s, arguments: args)
    }

    static let zh: [String: String] = [
        // 分類
        "unsorted": "未分類",
        "otherPlaces": "其他地點",
        "other": "其他",
        "videos": "影片",
        "dayFormat": "M月d日（EEE）",
        "group": "群組 %d",
        // 製作
        "subtitle.default": "點一個主題，想從哪裡開始都可以",
        "deck.title.default": "我的旅行",
        "outro.heading": "謝謝你來",
        "outro.cta": "掃描追蹤",
        // 進度
        "step.copy": "整理照片（%d／%d）",
        "step.build": "產生縮圖（%d／%d）",
        "step.ai": "AI 正在看照片⋯",
        "step.geocode": "查地點名稱（%d／%d）",
        "step.read": "讀取拍攝時間和地點（%d／%d）",
        "step.export": "從「照片」取出原始檔（%d／%d）",
        "step.done": "完成",
        // 錯誤
        "err.noPi": "找不到 AI 小幫手（Pi）。請重新安裝 App。",
        "err.notLoggedIn": "還沒用 ChatGPT 登入。",
        "err.aiFailed": "AI 沒有回應：%@",
        "err.aiBadReply": "AI 的回答看不懂，請再試一次。",
        "err.loginPort": "登入用的網路埠 1455 被佔用了（可能是 Codex 或 Pi 正在登入）。關掉它們再試一次。",
        "err.loginTimeout": "等太久沒有完成登入，請再試一次。",
        "err.loginFailed": "登入失敗：%@",
        "err.noPhotos": "還沒有挑照片。",
        "err.folderExists": "這個位置已經有同名資料夾了，換個名字吧。",
    ]

    static let en: [String: String] = [
        "unsorted": "Unsorted",
        "otherPlaces": "Other places",
        "other": "Other",
        "videos": "Videos",
        "dayFormat": "EEE, MMM d",
        "group": "Group %d",
        "subtitle.default": "Pick a topic — start anywhere you like",
        "deck.title.default": "My Trip",
        "outro.heading": "Thanks for coming",
        "outro.cta": "Scan to follow",
        "step.copy": "Organizing photos (%d/%d)",
        "step.build": "Making thumbnails (%d/%d)",
        "step.ai": "AI is looking at your photos…",
        "step.geocode": "Looking up place names (%d/%d)",
        "step.read": "Reading dates and locations (%d/%d)",
        "step.export": "Getting originals from Photos (%d/%d)",
        "step.done": "Done",
        "err.noPi": "The AI helper (Pi) is missing. Please reinstall the app.",
        "err.notLoggedIn": "Not signed in with ChatGPT yet.",
        "err.aiFailed": "The AI didn't respond: %@",
        "err.aiBadReply": "Couldn't understand the AI's reply. Please try again.",
        "err.loginPort": "Port 1455 is busy (Codex or Pi may be signing in). Close them and try again.",
        "err.loginTimeout": "Sign-in took too long. Please try again.",
        "err.loginFailed": "Sign-in failed: %@",
        "err.noPhotos": "No photos picked yet.",
        "err.folderExists": "A folder with this name already exists here. Pick another name.",
    ]
}

public struct WanderError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
