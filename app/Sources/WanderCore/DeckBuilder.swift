import Foundation

/// engine/build.py 的 Swift 版：掃描簡報資料夾，產生縮圖、大圖和 _wander/data.js。
/// 兩邊產出的 data.js 要一模一樣（有測試在比對）；改其中一邊，另一邊也要跟著改。
/// 跟 Python 版的差別只有工具：圖片用 ImageIO（不用 sips），影片封面用 AVFoundation（不用 ffmpeg）。
public final class DeckBuilder {
    public let root: URL
    let here: URL
    let thumbDir: URL
    let largeDir: URL
    public private(set) var warnings: [String] = []
    public private(set) var summary: [String] = []
    /// (已處理, 總數)
    public var progress: ((Int, Int) -> Void)?
    private var done = 0
    private var total = 0
    private let rootPath: String

    static let thumbPx = 480, largePx = 2400
    static let styleFormat = "wander-style/1"

    public init(deck: URL) {
        root = deck.standardizedFileURL.resolvingSymlinksInPath()
        here = root.appendingPathComponent("_wander")
        thumbDir = here.appendingPathComponent("thumbs")
        largeDir = here.appendingPathComponent("large")
        rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    }

    // MARK: 小工具

    func warn(_ s: String) { warnings.append(s) }
    static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    func rel(_ url: URL) -> String {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        return Self.nfc(p.hasPrefix(rootPath) ? String(p.dropFirst(rootPath.count)) : p)
    }

    func file(_ relPath: String) -> URL { root.appendingPathComponent(relPath) }

    static let numberPrefix = try! NSRegularExpression(pattern: #"^\s*\d+\s*[.、．)\-_ ]\s*"#)

    public static func displayName(_ folder: String) -> String {
        let r = NSRange(folder.startIndex..., in: folder)
        let out = numberPrefix.stringByReplacingMatches(in: folder, range: r, withTemplate: "")
        return out.isEmpty ? folder : out
    }

    func isFile(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && !d.boolValue
    }

    func mtime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func isStale(_ src: URL, _ out: URL) -> Bool {
        guard let o = mtime(out) else { return true }
        return o < (mtime(src) ?? .distantFuture)
    }

    static func withJPGSuffix(_ rel: String) -> String {
        let ns = rel as NSString
        return ns.deletingPathExtension + ".jpg"
    }

    func children(of dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { Self.nfc($0.lastPathComponent) < Self.nfc($1.lastPathComponent) }
    }

    func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    // MARK: 圖片

    func makePhoto(_ src: URL, _ out: URL, size: Int, quality: Double) -> Bool {
        if !isStale(src, out) { return true }
        if !ImageTools.makeJPEG(from: src, to: out, maxPixel: size, quality: quality) {
            warn("無法轉換圖片：\(rel(src))")
            return false
        }
        return true
    }

    func ratio(_ url: URL) -> Double {
        let (w, h) = ImageTools.pixelSize(url) ?? (4, 3)
        return (Double(w) / Double(h) * 10000).rounded() / 10000
    }

    // MARK: 主題

    func mediaFiles(_ folder: URL) -> [URL] { children(of: folder).filter { isFile($0) } }

    func collectItems(_ folder: URL) -> [[String: Any]] {
        var items: [[String: Any]] = []
        for f in mediaFiles(folder) {
            let ext = f.pathExtension.lowercased()
            let key = Self.withJPGSuffix(rel(f))
            let thumb = thumbDir.appendingPathComponent(key), large = largeDir.appendingPathComponent(key)
            if MediaTypes.photo.contains(ext) {
                if makePhoto(f, thumb, size: Self.thumbPx, quality: 0.78) && makePhoto(f, large, size: Self.largePx, quality: 0.84) {
                    items.append(["type": "photo", "src": rel(large), "thumb": rel(thumb), "ratio": ratio(thumb)])
                }
                tick()
            } else if MediaTypes.video.contains(ext) {
                let has = isStale(f, thumb) ? ImageTools.videoPoster(f, to: thumb, maxPixel: Self.thumbPx) : isFile(thumb)
                items.append(["type": "video", "src": rel(f), "thumb": has ? rel(thumb) : NSNull(),
                              "ratio": has ? ratio(thumb) : 16.0 / 9.0])
                tick()
            }
        }
        return items
    }

    func tick() { done += 1; progress?(done, total) }

    func buildTopic(_ folder: URL, _ cfg: [String: Any]) -> [String: Any] {
        let name = Self.nfc(folder.lastPathComponent)
        let topics = cfg["topics"] as? [String: Any] ?? [:]
        let labels = topics["labels"] as? [String: Any] ?? [:]
        var t: [String: Any] = ["id": name, "name": (labels[name] as? String) ?? Self.displayName(name),
                                "items": collectItems(folder), "children": [[String: Any]]()]
        if (topics["walls"] as? [String] ?? []).contains(name) { t["layout"] = "wall" }
        var kids: [[String: Any]] = []
        for sub in children(of: folder) where isDir(sub) && !sub.lastPathComponent.hasPrefix("_") {
            let child = buildTopic(sub, cfg)
            if !(child["items"] as! [Any]).isEmpty || !(child["children"] as! [Any]).isEmpty { kids.append(child) }
        }
        t["children"] = kids
        return t
    }

    static func covers(_ t: [String: Any], _ n: Int = 3) -> [String] {
        var thumbs = (t["items"] as! [[String: Any]]).compactMap { $0["thumb"] as? String }
        thumbs = Array(thumbs.prefix(n))
        for c in t["children"] as! [[String: Any]] {
            if thumbs.count >= n { break }
            thumbs += covers(c, n - thumbs.count)
        }
        return thumbs
    }

    static func attachCovers(_ t: inout [String: Any]) {
        t["covers"] = covers(t)
        var kids = t["children"] as! [[String: Any]]
        for i in kids.indices { attachCovers(&kids[i]) }
        t["children"] = kids
    }

    static func allItems(_ t: [String: Any]) -> [[String: Any]] {
        (t["items"] as! [[String: Any]]) + (t["children"] as! [[String: Any]]).flatMap { allItems($0) }
    }

    func removeUnused(_ folder: URL, used: Set<String>) {
        let fm = FileManager.default
        guard isDir(folder), let en = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        var dirs: [URL] = []
        for case let f as URL in en {
            if isDir(f) { dirs.append(f) } else if !used.contains(rel(f)) { try? fm.removeItem(at: f) }
        }
        for d in dirs.sorted(by: { $0.pathComponents.count > $1.pathComponents.count })
        where ((try? fm.contentsOfDirectory(atPath: d.path)) ?? ["x"]).isEmpty {
            try? fm.removeItem(at: d)
        }
    }

    // MARK: 設定

    static let defaults: [String: Any] = [
        "title": "漫遊簡報", "subtitle": "點一個主題，想從哪裡開始都可以", "lang": "zh-Hant-TW",
        "theme": [String: Any](), "background": NSNull(), "logo": NSNull(),
        "music": ["file": NSNull(), "volume": 50] as [String: Any],
        "topics": ["order": [Any](), "hidden": [Any](), "walls": [Any](), "labels": [String: Any]()] as [String: Any],
        "intro": [Any](), "scenes": [String: Any](), "outro": NSNull(), "text": [String: Any](), "style": NSNull(),
    ]

    func loadConfig() throws -> ([String: Any], Set<String>) {
        var cfg = Self.defaults
        var userKeys = Set<String>()
        let cfgFile = root.appendingPathComponent("deck.json")
        if isFile(cfgFile) {
            let data = try Data(contentsOf: cfgFile)
            guard let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WanderError("deck.json 格式錯誤")
            }
            userKeys = Set(user.keys)
            for (k, v) in user {
                if let dv = v as? [String: Any], var base = cfg[k] as? [String: Any] {
                    base.merge(dv) { _, new in new }
                    cfg[k] = base
                } else {
                    cfg[k] = v
                }
            }
        } else {
            warn("找不到 deck.json，全部用預設值")
        }
        var t = cfg["topics"] as? [String: Any] ?? [:]
        for k in ["order", "hidden", "walls"] { t[k] = (t[k] as? [Any] ?? []).compactMap { ($0 as? String).map(Self.nfc) } }
        var labels: [String: Any] = [:]
        for (k, v) in t["labels"] as? [String: Any] ?? [:] { labels[Self.nfc(k)] = v }
        t["labels"] = labels
        cfg["topics"] = t
        return (cfg, userKeys)
    }

    static func stylePath(_ p: Any?) -> Any {
        guard let s = p as? String, !s.isEmpty else { return NSNull() }
        return "_style/" + s
    }

    static func deepCopy(_ v: Any) -> Any {
        guard JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v) else { return v }
        return (try? JSONSerialization.jsonObject(with: d)) ?? v
    }

    func loadStyle(_ cfg: inout [String: Any], userKeys: Set<String>) {
        cfg["css"] = NSNull()
        guard let want = cfg["style"] as? String, !want.isEmpty else { return }
        let meta = root.appendingPathComponent("_style/style.json")
        guard isFile(meta) else {
            warn("style 設成「\(want)」，但簡報資料夾裡沒有 _style/style.json，先用預設外觀")
            return
        }
        guard let data = try? Data(contentsOf: meta),
              let st = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            warn("_style/style.json 格式錯誤，先用預設外觀")
            return
        }
        if st["format"] as? String != Self.styleFormat { warn("_style/style.json 的 format 應該是「\(Self.styleFormat)」") }
        if st["id"] as? String != want { warn("deck.json 要的是風格「\(want)」，但 _style 裡裝的是「\(st["id"] as? String ?? "None")」") }

        var theme = st["theme"] as? [String: Any] ?? [:]
        if userKeys.contains("theme") { theme.merge(cfg["theme"] as? [String: Any] ?? [:]) { _, n in n } }
        cfg["theme"] = theme
        if !((cfg["background"] as? String).map { !$0.isEmpty } ?? false), let bg = st["background"] as? String, !bg.isEmpty {
            cfg["background"] = Self.stylePath(bg)
        }
        if let css = st["css"] as? String, !css.isEmpty {
            cfg["css"] = checkAsset(Self.stylePath(css), "風格包的 css")
        }
        if !userKeys.contains("music"), let m = st["music"] as? [String: Any] {
            cfg["music"] = ["file": Self.stylePath(m["file"]), "volume": m["volume"] ?? 50]
        }
        var scenes: [String: Any] = [:]
        for (name, raw) in st["scenes"] as? [String: Any] ?? [:] {
            var sc = Self.deepCopy(raw) as? [String: Any] ?? [:]
            sc["background"] = Self.stylePath(sc["background"])
            sc["layers"] = (sc["layers"] as? [[String: Any]] ?? []).map { l -> [String: Any] in
                var l = l
                l["src"] = Self.stylePath(l["src"])
                return l
            }
            scenes[name] = sc
        }
        if userKeys.contains("scenes") { scenes.merge(cfg["scenes"] as? [String: Any] ?? [:]) { _, n in n } }
        cfg["scenes"] = scenes

        if !userKeys.contains("intro") || (cfg["intro"] as? String) == "style" {
            let pages = (Self.deepCopy(st["intro"] ?? [Any]()) as? [Any] ?? []).map { raw -> Any in
                guard var p = raw as? [String: Any] else { return raw }
                if (p["type"] as? String ?? "image") == "image", let s = p["src"] as? String, !s.isEmpty {
                    p["src"] = Self.stylePath(s)
                }
                if let cards = p["cards"] as? [[String: Any]] {
                    p["cards"] = cards.map { c -> [String: Any] in
                        var c = c
                        if let fr = c["frame"] as? String, !fr.isEmpty { c["frame"] = Self.stylePath(fr) }
                        return c
                    }
                }
                return p
            }
            cfg["intro"] = pages
        }
    }

    func fillText(_ s: Any?, _ cfg: [String: Any]) -> String {
        String(describing: s ?? "")
            .replacingOccurrences(of: "{title}", with: cfg["title"] as? String ?? "")
            .replacingOccurrences(of: "{subtitle}", with: cfg["subtitle"] as? String ?? "")
    }

    func checkAsset(_ path: Any?, _ what: String) -> Any {
        guard let p = path as? String, !p.isEmpty else { return NSNull() }
        if !isFile(file(p)) {
            warn("\(what) 找不到檔案：\(p)")
            return NSNull()
        }
        return p
    }

    func resolveAssets(_ cfg: inout [String: Any]) {
        cfg["background"] = checkAsset(cfg["background"], "background（背景圖）")
        cfg["logo"] = checkAsset(cfg["logo"], "logo")
        var m: [String: Any] = (cfg["music"] as? [String: Any]) ?? ["file": cfg["music"] ?? NSNull()]
        m["file"] = checkAsset(m["file"], "music（背景音樂）")
        if let f = m["file"] as? String,
           ((try? FileManager.default.attributesOfItem(atPath: file(f).path))?[.size] as? Int ?? 1) == 0 {
            warn("背景音樂是空檔案（0 KB），通常是下載失敗：\(f)")
            m["file"] = NSNull()
        }
        m["volume"] = max(0, min(100, (m["volume"] as? NSNumber)?.intValue ?? Int("\(m["volume"] ?? 50)") ?? 50))
        cfg["music"] = m

        var scenes = cfg["scenes"] as? [String: Any] ?? [:]
        for (name, raw) in scenes {
            var sc = raw as? [String: Any] ?? [:]
            sc["background"] = checkAsset(sc["background"], "scenes.\(name).background")
            if let bg = sc["background"] as? String, sc["size"] == nil {
                let (w, h) = ImageTools.pixelSize(file(bg)) ?? (4, 3)
                sc["size"] = [w, h]
            }
            var layers: [[String: Any]] = []
            for var l in sc["layers"] as? [[String: Any]] ?? [] {
                l["src"] = checkAsset(l["src"], "scenes.\(name) 的圖層")
                if l["src"] is String { layers.append(l) }
            }
            sc["layers"] = layers
            scenes[name] = sc
        }
        cfg["scenes"] = scenes

        var pages: [Any] = []
        for (i0, raw) in (cfg["intro"] as? [Any] ?? []).enumerated() {
            let i = i0 + 1
            var p: [String: Any] = (raw as? String).map { ["type": "image", "src": $0] } ?? (raw as? [String: Any] ?? [:])
            let type = p["type"] as? String ?? "image"
            if type == "image" {
                if checkAsset(p["src"], "intro 第 \(i) 頁") is String { pages.append(p) }
                continue
            }
            if type == "scene" {
                let sc = (cfg["scenes"] as? [String: Any])?[p["scene"] as? String ?? ""] as? [String: Any]
                if sc == nil || !(sc?["background"] is String) {
                    warn("intro 第 \(i) 頁：scene「\(p["scene"] as? String ?? "None")」沒有設定或缺背景，這頁略過")
                    continue
                }
                if var title = p["title"] as? [String: Any], !title.isEmpty {
                    if let text = title["text"], !(text is NSNull), !"\(text)".isEmpty {
                        title["text"] = fillText(text, cfg)
                        title.removeValue(forKey: "src")
                    } else {
                        title["src"] = checkAsset(title["src"], "intro 第 \(i) 頁的標題圖")
                    }
                    p["title"] = title
                }
                let texts = (p["texts"] as? [[String: Any]] ?? []).map { tx -> [String: Any] in
                    var tx = tx
                    tx["text"] = fillText(tx["text"] ?? "", cfg)
                    return tx
                }
                p["texts"] = texts.filter { !($0["text"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if (p["cards"] as? String) != "auto" {
                    var cards: [[String: Any]] = []
                    for var c in p["cards"] as? [[String: Any]] ?? [] {
                        c["photo"] = checkAsset(c["photo"], "intro 第 \(i) 頁的拍立得照片")
                        if let fr = c["frame"], !(fr is NSNull), !"\(fr)".isEmpty {
                            c["frame"] = checkAsset(fr, "intro 第 \(i) 頁的拍立得相框")
                        }
                        if c["photo"] is String { cards.append(c) }
                    }
                    p["cards"] = cards
                }
                pages.append(p)
            } else {
                warn("intro 第 \(i) 頁：不認得的 type「\(type)」")
            }
        }
        cfg["intro"] = pages

        if var o = cfg["outro"] as? [String: Any] {
            o["qr"] = checkAsset(o["qr"], "outro.qr（QR code 圖）")
            if let fr = o["frame"], !(fr is NSNull), !"\(fr)".isEmpty { o["frame"] = checkAsset(fr, "outro.frame") }
            cfg["outro"] = o
        }
    }

    func resizedAsset(_ path: String, px: Int) -> String {
        if path.hasPrefix("_wander/") { return path }
        let src = file(path)
        let ext = src.pathExtension.lowercased()
        if !MediaTypes.photo.contains(ext) || ext == "png" { return path }
        let out = here.appendingPathComponent("assets").appendingPathComponent(Self.withJPGSuffix(path))
        return makePhoto(src, out, size: px, quality: 0.88) ? rel(out) : path
    }

    func fillAutoCards(_ cfg: inout [String: Any], topics: [[String: Any]]) {
        var pages = cfg["intro"] as? [Any] ?? []
        for i in pages.indices {
            guard var p = pages[i] as? [String: Any], (p["cards"] as? String) == "auto" else { continue }
            let slots = p.removeValue(forKey: "cardSlots") as? [[String: Any]] ?? []
            let picks: [(String, [String: Any])] = topics.compactMap { t in
                guard let item = Self.allItems(t).first(where: { $0["type"] as? String == "photo" }) else { return nil }
                return (t["name"] as! String, item)
            }
            var cards: [[String: Any]] = []
            for (slot, (name, item)) in zip(slots, picks) {
                var c = slot
                c["photo"] = item["src"]
                c["caption"] = slot["caption"] ?? name
                cards.append(c)
            }
            p["cards"] = cards
            pages[i] = p
        }
        cfg["intro"] = pages
    }

    // MARK: 主程式

    @discardableResult
    public func run(checkOnly: Bool = false) throws -> Bool {
        warnings = []; summary = []
        var (cfg, userKeys) = try loadConfig()
        loadStyle(&cfg, userKeys: userKeys)
        resolveAssets(&cfg)

        var t = cfg["topics"] as! [String: Any]
        let hidden = t["hidden"] as! [String]
        let order = t["order"] as! [String]
        var folders = children(of: root).filter {
            isDir($0) && !$0.lastPathComponent.hasPrefix("_") && !hidden.contains(Self.nfc($0.lastPathComponent))
        }
        let names = folders.map { Self.nfc($0.lastPathComponent) }
        var allNames = Set<String>()
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles]) {
            for case let d as URL in en {
                if d.lastPathComponent.hasPrefix("_") { en.skipDescendants(); continue }
                if isDir(d) { allNames.insert(Self.nfc(d.lastPathComponent)) }
            }
        }
        for key in ["order", "hidden", "walls"] {
            for n in t[key] as! [String] where !(key == "order" ? names.contains(n) : allNames.contains(n)) {
                warn("topics.\(key) 裡的「\(n)」找不到這個資料夾")
            }
        }
        for n in (t["labels"] as! [String: Any]).keys.sorted() where !allNames.contains(n) {
            warn("topics.labels 裡的「\(n)」找不到這個資料夾")
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        folders.sort {
            let a = Self.nfc($0.lastPathComponent), b = Self.nfc($1.lastPathComponent)
            return (rank[a] ?? rank.count, a) < (rank[b] ?? rank.count, b)
        }
        t["order"] = order
        let labels = t["labels"] as! [String: Any]

        if checkOnly {
            summary.append("主題順序：" + folders.map {
                (labels[Self.nfc($0.lastPathComponent)] as? String) ?? Self.displayName(Self.nfc($0.lastPathComponent))
            }.joined(separator: "、"))
            return warnings.isEmpty
        }

        total = countMedia(folders)
        done = 0
        var topics: [[String: Any]] = []
        for d in folders {
            var tp = buildTopic(d, cfg)
            if !(tp["items"] as! [Any]).isEmpty || !(tp["children"] as! [Any]).isEmpty {
                Self.attachCovers(&tp)
                topics.append(tp)
            }
            let n = Self.allItems(tp).count
            let kids = (tp["children"] as! [Any]).count
            summary.append("  \(tp["name"] as! String)：\(n) 個檔案" + (kids > 0 ? "，\(kids) 個子主題" : ""))
        }
        var used = Set<String>()
        for tp in topics { for i in Self.allItems(tp) { for k in ["thumb", "src"] { if let s = i[k] as? String { used.insert(s) } } } }
        removeUnused(thumbDir, used: used)
        removeUnused(largeDir, used: used)
        fillAutoCards(&cfg, topics: topics)
        var pages = cfg["intro"] as? [Any] ?? []
        for i in pages.indices {
            guard var p = pages[i] as? [String: Any], let cards = p["cards"] as? [[String: Any]] else { continue }
            p["cards"] = cards.map { c -> [String: Any] in
                var c = c
                if let ph = c["photo"] as? String { c["photo"] = resizedAsset(ph, px: 1600) }
                return c
            }
            pages[i] = p
        }
        cfg["intro"] = pages

        var data: [String: Any] = [:]
        for k in ["title", "subtitle", "lang", "theme", "background", "logo", "music", "intro", "scenes", "outro", "text", "css"] {
            data[k] = cfg[k] ?? NSNull()
        }
        data["topics"] = topics
        let json = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try FileManager.default.createDirectory(at: here, withIntermediateDirectories: true)
        var out = Data("window.WANDER = ".utf8)
        out.append(json)
        out.append(Data(";\n".utf8))
        try out.write(to: here.appendingPathComponent("data.js"), options: .atomic)
        return true
    }

    func countMedia(_ folders: [URL]) -> Int {
        var n = 0
        for f in folders {
            guard let en = FileManager.default.enumerator(at: f, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let u as URL in en {
                if u.lastPathComponent.hasPrefix("_") { en.skipDescendants(); continue }
                if MediaTypes.kind(of: u) != nil { n += 1 }
            }
        }
        return n
    }
}
