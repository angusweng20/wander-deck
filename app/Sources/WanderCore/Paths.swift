import Foundation

/// App 要用到的檔案放在哪裡。
/// 打包好的 .app：引擎、風格包、Pi 都在 Contents/Resources。
/// 開發時（swift run）：直接用專案資料夾裡的 engine/、styles/。
public enum Paths {
    /// 專案根目錄或 .app 的 Resources；裡面有 engine/、styles/，可能還有 pi/。
    public static let resources: URL = {
        if let env = ProcessInfo.processInfo.environment["WANDER_ROOT"] {
            return URL(fileURLWithPath: env)
        }
        // .app/Contents/MacOS/執行檔 → .app/Contents/Resources
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = exe.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("engine/deck.html").path) {
            return bundled
        }
        if let main = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: main.appendingPathComponent("engine/deck.html").path) {
            return main
        }
        // 開發中：這個檔案在 app/Sources/WanderCore/，往上三層是專案根目錄
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }()

    public static var engine: URL { resources.appendingPathComponent("engine") }
    public static var bundledStyles: URL { resources.appendingPathComponent("styles") }

    /// ~/Library/Application Support/Wander Deck
    public static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // 測試時改放到暫存資料夾，不碰使用者真正的設定
        let dir = ProcessInfo.processInfo.environment["WANDER_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? base.appendingPathComponent("Wander Deck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 使用者自己匯入的風格包
    public static var userStyles: URL {
        let d = support.appendingPathComponent("styles", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// App 專用的 Pi 設定（登入資料只放這裡，不碰使用者自己的 ~/.pi）
    public static var piAgentDir: URL {
        let d = support.appendingPathComponent("pi-agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return d
    }

    public static let caches: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Wander Deck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 預設把新簡報放在「文件／漫遊簡報」
    public static var defaultDecksFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(L10n.isEnglish ? "Wander Decks" : "漫遊簡報", isDirectory: true)
    }
}
