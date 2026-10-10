import Foundation

/// 一個風格包（格式見 docs/style-pack.md）。
public struct StylePack: Identifiable, Hashable, Sendable {
    public let id: String
    public let folder: URL
    public let names: [String: String]
    public let descriptions: [String: String]
    public let countries: [String]
    public let version: String
    public let author: String
    public let license: String
    public let preview: URL?
    public let isBuiltIn: Bool

    public var name: String { localized(names) ?? id }
    public var summary: String { localized(descriptions) ?? "" }

    func localized(_ d: [String: String]) -> String? {
        L10n.isEnglish ? (d["en"] ?? d["zh-Hant"] ?? d.values.first) : (d["zh-Hant"] ?? d["en"] ?? d.values.first)
    }
}

public enum StyleLibrary {
    public static let format = "wander-style/1"
    public static let defaultID = "watercolor"
    static let allowedExt: Set<String> = ["json", "css", "md", "txt", "jpg", "jpeg", "png", "webp", "gif",
                                          "mp3", "m4a", "aac", "woff", "woff2", "otf", "ttf"]
    static let maxTotal = 80 * 1024 * 1024
    static let maxFiles = 400
    static let licenses: Set<String> = ["CC-BY-4.0", "CC-BY-SA-4.0", "CC0-1.0"]

    /// App 內建的＋使用者匯入的（同 id 時用使用者的）
    public static func all() -> [StylePack] {
        var byID: [String: StylePack] = [:]
        for (dir, builtIn) in [(Paths.bundledStyles, true), (Paths.userStyles, false)] {
            let subs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for s in subs where !s.lastPathComponent.hasPrefix(".") {
                if let p = load(s, builtIn: builtIn) { byID[p.id] = p }
            }
        }
        let order = ["watercolor", "ukiyoe", "classic"]
        return byID.values.sorted {
            (order.firstIndex(of: $0.id) ?? 99, $0.name) < (order.firstIndex(of: $1.id) ?? 99, $1.name)
        }
    }

    public static func load(_ folder: URL, builtIn: Bool = false) -> StylePack? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("style.json")),
              let st = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              st["format"] as? String == format, let id = st["id"] as? String else { return nil }
        func dict(_ v: Any?) -> [String: String] {
            if let s = v as? String { return ["zh-Hant": s] }
            return v as? [String: String] ?? [:]
        }
        let preview = (st["preview"] as? String).map { folder.appendingPathComponent($0) }
        return StylePack(id: id, folder: folder, names: dict(st["name"]), descriptions: dict(st["description"]),
                         countries: st["countries"] as? [String] ?? [], version: st["version"] as? String ?? "",
                         author: st["author"] as? String ?? "", license: st["license"] as? String ?? "",
                         preview: preview.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
                         isBuiltIn: builtIn)
    }

    /// 依照片拍攝的國家挑風格：有專屬風格就用，沒有就用水彩
    public static func best(forCountry code: String?, in packs: [StylePack] = all()) -> StylePack? {
        if let code, let hit = packs.first(where: { $0.countries.contains(code) }) { return hit }
        return packs.first { $0.id == defaultID } ?? packs.first
    }

    // MARK: 檢查（跟 scripts/style_pack.py 的 check 規則一樣）

    public static func problems(in folder: URL) -> [String] {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("style.json")) else { return ["沒有 style.json"] }
        guard let st = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ["style.json 格式錯誤"] }
        var out: [String] = []
        if st["format"] as? String != format { out.append("format 要寫「\(format)」") }
        let id = st["id"] as? String ?? ""
        if id.range(of: #"^[a-z0-9][a-z0-9-]{1,39}$"#, options: .regularExpression) == nil { out.append("id 只能用小寫英文、數字和 -") }
        if (st["name"] as? String)?.isEmpty ?? ((st["name"] as? [String: String])?.isEmpty ?? true) { out.append("缺 name") }
        if (st["version"] as? String)?.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) == nil { out.append("version 要像 1.0.0") }
        if (st["author"] as? String ?? "").trimmingCharacters(in: .whitespaces).isEmpty { out.append("缺 author") }
        if !licenses.contains(st["license"] as? String ?? "") { out.append("license 不在允許清單") }
        if (st["credits"] as? String ?? "").isEmpty { out.append("缺 credits") }
        for (what, p) in referencedFiles(st) {
            if p.hasPrefix("/") || p.split(separator: "/").contains("..") { out.append("\(what)：路徑不合法") }
            else if !fm.fileExists(atPath: folder.appendingPathComponent(p).path) { out.append("\(what)：找不到 \(p)") }
        }
        var total = 0, count = 0
        if let en = fm.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in en {
                let v = try? f.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
                if v?.isSymbolicLink == true { out.append("不能有捷徑：\(f.lastPathComponent)"); continue }
                guard v?.isRegularFile == true, !f.lastPathComponent.hasPrefix(".") else { continue }
                count += 1
                total += v?.fileSize ?? 0
                if !allowedExt.contains(f.pathExtension.lowercased()) { out.append("不收這種檔案：\(f.lastPathComponent)") }
            }
        }
        if let css = st["css"] as? String,
           let text = try? String(contentsOf: folder.appendingPathComponent(css), encoding: .utf8),
           text.range(of: #"@import|url\(\s*['"]?\s*(https?:|//|file:|javascript:)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            out.append("css 不能載入網路上的東西")
        }
        if total > maxTotal { out.append("整包超過 80MB") }
        if count > maxFiles { out.append("檔案超過 \(maxFiles) 個") }
        return out
    }

    static func referencedFiles(_ st: [String: Any]) -> [(String, String)] {
        var refs: [(String, String)] = []
        for k in ["background", "css", "preview", "credits"] { if let v = st[k] as? String, !v.isEmpty { refs.append((k, v)) } }
        if let f = (st["music"] as? [String: Any])?["file"] as? String { refs.append(("music", f)) }
        for (name, raw) in st["scenes"] as? [String: Any] ?? [:] {
            let sc = raw as? [String: Any] ?? [:]
            if let b = sc["background"] as? String { refs.append(("scenes.\(name)", b)) }
            for l in sc["layers"] as? [[String: Any]] ?? [] { refs.append(("scenes.\(name) 圖層", l["src"] as? String ?? "")) }
        }
        return refs
    }

    // MARK: 匯入、匯出、裝進簡報

    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        if p.terminationStatus != 0 { throw WanderError(text.isEmpty ? "\(tool) 失敗" : text) }
        return text
    }

    /// 匯入 .wdstyle（其實是 zip）。先看清單、只收白名單檔案，再解開檢查。
    @discardableResult
    public static func importPack(_ file: URL) throws -> StylePack {
        let names = try run("/usr/bin/zipinfo", ["-1", file.path]).split(separator: "\n").map(String.init)
        if names.count > maxFiles { throw WanderError(L10n.isEnglish ? "Too many files in the pack." : "風格包裡的檔案太多。") }
        for n in names where !n.hasSuffix("/") {
            let parts = n.split(separator: "/").map(String.init)
            if n.hasPrefix("/") || parts.contains("..") { throw WanderError("Unsafe path: \(n)") }
            if parts.contains(where: { $0.hasPrefix("__MACOSX") }) || (parts.last ?? "").hasPrefix(".") { continue }
            let ext = (n as NSString).pathExtension.lowercased()
            if !allowedExt.contains(ext) {
                throw WanderError(L10n.isEnglish ? "The pack contains a file type that isn't allowed: \(n)"
                                                 : "風格包裡有不收的檔案類型：\(n)")
            }
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wdstyle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", file.path, tmp.path])
        let metas = (FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.lastPathComponent == "style.json" && !$0.path.contains("__MACOSX") }
        guard metas.count == 1 else { throw WanderError(L10n.isEnglish ? "The pack must contain exactly one style.json." : "風格包裡要剛好有一個 style.json。") }
        let root = metas[0].deletingLastPathComponent()
        let issues = problems(in: root)
        if !issues.isEmpty { throw WanderError(issues.joined(separator: "\n")) }
        guard let pack = load(root) else { throw WanderError("style.json") }
        let dest = Paths.userStyles.appendingPathComponent(pack.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            let backup = Paths.userStyles.appendingPathComponent(".\(pack.id)-backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: dest, to: backup)
        }
        try FileManager.default.copyItem(at: root, to: dest)
        // 解開的檔案不帶執行權限
        _ = try? run("/bin/chmod", ["-R", "a-x,u+rwX,go+rX", dest.path])
        return load(dest)!
    }

    public static func export(_ pack: StylePack, to file: URL) throws {
        let issues = problems(in: pack.folder)
        if !issues.isEmpty { throw WanderError(issues.joined(separator: "\n")) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wdstyle-out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let staged = tmp.appendingPathComponent(pack.id)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: pack.folder, to: staged)
        try? FileManager.default.removeItem(at: file)
        _ = try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--keepParent", staged.path, file.path])
    }

    /// 把風格包複製到簡報的 _style/
    public static func install(_ pack: StylePack, into deck: URL) throws {
        let target = deck.appendingPathComponent("_style")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: pack.folder, to: target)
    }
}
