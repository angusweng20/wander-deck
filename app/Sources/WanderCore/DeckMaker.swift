import Foundation

/// 要做一份什麼樣的簡報
public struct DeckSpec: Sendable {
    public var title: String
    public var subtitle: String
    public var parentFolder: URL
    public var groups: [PhotoGroup]
    public var items: [String: PhotoItem]
    public var style: StylePack?
    public var music: URL?
    public var musicVolume: Int = 50
    public var qrImage: URL?
    public var qrHandle: String = ""

    public init(title: String, subtitle: String, parentFolder: URL, groups: [PhotoGroup],
                items: [String: PhotoItem], style: StylePack?) {
        self.title = title; self.subtitle = subtitle; self.parentFolder = parentFolder
        self.groups = groups; self.items = items; self.style = style
    }
}

public struct MakeProgress: Sendable {
    public var message: String
    public var fraction: Double
}

/// 「照片」App 的照片要先取出原始檔，才能放進簡報資料夾
public typealias AssetExporter = @Sendable (_ item: PhotoItem, _ folder: URL) async throws -> URL

/// 把挑好、分好的照片做成一份簡報資料夾。原始照片只複製、不移動、不修改。
public enum DeckMaker {
    public static var htmlName: String { L10n.isEnglish ? "Presentation.html" : "簡報.html" }
    public static var openName: String { L10n.isEnglish ? "Open Presentation.command" : "打開簡報.command" }
    public static var updateName: String { L10n.isEnglish ? "Update Presentation.command" : "更新簡報.command" }

    public static func uniqueFolder(in parent: URL, name: String) -> URL {
        let base = Grouping.safeName(name)
        var url = parent.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(base) \(n)", isDirectory: true)
            n += 1
        }
        return url
    }

    public static func make(_ spec: DeckSpec, exporter: AssetExporter? = nil,
                            progress: @escaping @Sendable (MakeProgress) -> Void) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: spec.parentFolder, withIntermediateDirectories: true)
        let deck = uniqueFolder(in: spec.parentFolder, name: spec.title.isEmpty ? L10n.t("deck.title.default") : spec.title)
        try fm.createDirectory(at: deck, withIntermediateDirectories: true)
        try installEngine(into: deck)
        if let style = spec.style { try StyleLibrary.install(style, into: deck) }

        // 1. 照片放進主題資料夾（01 京都、02 大阪⋯）
        let total = spec.groups.reduce(0) { $0 + $1.count }
        var copied = 0
        var order: [String] = []
        var walls: [String] = []
        func place(_ g: PhotoGroup, index: Int, in parent: URL) async throws -> String {
            let folderName = String(format: "%02d %@", index + 1, Grouping.safeName(g.name))
            let dir = parent.appendingPathComponent(folderName, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for id in g.itemIDs {
                guard let item = spec.items[id] else { continue }
                try Task.checkCancellation()
                if let src = item.fileURL {
                    try copy(src, into: dir)
                } else if item.assetID != nil, let exporter {
                    _ = try await exporter(item, dir)
                }
                copied += 1
                progress(MakeProgress(message: L10n.t("step.copy", copied, total), fraction: 0.5 * Double(copied) / Double(max(total, 1))))
            }
            for (i, c) in g.children.enumerated() { _ = try await place(c, index: i, in: dir) }
            // 照片少（2–4 張）又沒有子主題：用展示牆，大大的並排
            let photos = g.itemIDs.compactMap { spec.items[$0] }.filter { $0.kind == .photo }.count
            if g.children.isEmpty, (2...4).contains(photos), photos == g.itemIDs.count { walls.append(folderName) }
            return folderName
        }
        for (i, g) in spec.groups.enumerated() where g.count > 0 {
            order.append(try await place(g, index: i, in: deck))
        }

        // 2. 音樂、QR code
        let assets = deck.appendingPathComponent("_assets", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        var cfg: [String: Any] = [
            "title": spec.title.isEmpty ? L10n.t("deck.title.default") : spec.title,
            "subtitle": spec.subtitle,
            "lang": L10n.deckLang,
            "topics": ["order": order, "hidden": [String](), "walls": walls, "labels": [String: String]()],
        ]
        if let style = spec.style { cfg["style"] = style.id }
        if let m = spec.music {
            let name = "music." + m.pathExtension.lowercased()
            try fm.copyItem(at: m, to: assets.appendingPathComponent(name))
            cfg["music"] = ["file": "_assets/\(name)", "volume": spec.musicVolume]
        }
        if let qr = spec.qrImage {
            let name = "qr." + qr.pathExtension.lowercased()
            try fm.copyItem(at: qr, to: assets.appendingPathComponent(name))
            cfg["outro"] = ["qr": "_assets/\(name)", "handle": spec.qrHandle,
                            "heading": L10n.t("outro.heading"), "cta": L10n.t("outro.cta"), "tagline": spec.title]
        }
        let json = try JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try json.write(to: deck.appendingPathComponent("deck.json"))

        // 3. 產生縮圖、大圖、data.js
        let builder = DeckBuilder(deck: deck)
        builder.progress = { d, t in
            progress(MakeProgress(message: L10n.t("step.build", d, t), fraction: 0.5 + 0.5 * Double(d) / Double(max(t, 1))))
        }
        try builder.run()
        progress(MakeProgress(message: L10n.t("step.done"), fraction: 1))
        return deck
    }

    /// 複製一個檔案到資料夾，同名就加編號（APFS 上是「複製但不佔空間」的 clone）
    @discardableResult
    public static func copy(_ src: URL, into dir: URL) throws -> URL {
        let dest = uniqueFile(in: dir, name: src.lastPathComponent)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    public static func uniqueFile(in dir: URL, name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// 簡報.html、_wander/build.py、兩個 .command
    public static func installEngine(into deck: URL) throws {
        let fm = FileManager.default
        let engine = Paths.engine
        try fm.createDirectory(at: deck.appendingPathComponent("_wander"), withIntermediateDirectories: true)
        let pairs: [(String, String)] = [
            ("deck.html", htmlName),
            ("build.py", "_wander/build.py"),
            ("launchers/打開簡報.command", openName),
            ("launchers/更新簡報.command", updateName),
        ]
        for (from, to) in pairs {
            let dest = deck.appendingPathComponent(to)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: engine.appendingPathComponent(from), to: dest)
        }
        for name in [openName, updateName] {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deck.appendingPathComponent(name).path)
        }
    }
}
