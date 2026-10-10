import Foundation

/// 請 AI 看照片：幫主題取名、寫標題，或把照片分進主題。
/// 送出去的一律是縮小、清掉拍攝資訊的縮圖（ImageTools.aiThumbnail），不送原始檔、不送 GPS。
public struct AIService: Sendable {
    let pi: PiClient
    /// 從 PhotoItem 拿縮圖（檔案或「照片」App 都行）
    let thumbnail: @Sendable (PhotoItem, Int) async -> Data?

    public init(pi: PiClient, thumbnail: @escaping @Sendable (PhotoItem, Int) async -> Data?) {
        self.pi = pi
        self.thumbnail = thumbnail
    }

    var language: String { L10n.isEnglish ? "English" : "繁體中文（台灣用語）" }

    /// 平均挑幾張代表
    static func sample<T>(_ list: [T], _ n: Int) -> [T] {
        guard list.count > n, n > 0 else { return list }
        return (0..<n).map { list[$0 * list.count / n] }
    }

    public struct Naming: Sendable {
        public var title: String
        public var subtitle: String
        public var names: [UUID: String]
    }

    /// 幫每個主題取名，並給整份簡報標題、副標
    public func nameGroups(_ groups: [PhotoGroup], items: [String: PhotoItem], perGroup: Int = 6) async throws -> Naming {
        var flat: [PhotoGroup] = []
        func walk(_ g: PhotoGroup) { flat.append(g); g.children.forEach(walk) }
        groups.forEach(walk)
        let unsorted = [L10n.t("unsorted"), L10n.t("other")]
        flat = Array(flat.filter { !unsorted.contains($0.name) }.prefix(16))
        var images: [Data] = []
        var lines: [String] = []
        for (i, g) in flat.enumerated() {
            let picks = Self.sample(g.allItemIDs.compactMap { items[$0] }.filter { $0.kind == .photo }, perGroup)
            var n = 0
            for p in picks { if let d = await thumbnail(p, 384) { images.append(d); n += 1 } }
            lines.append("G\(i + 1)「\(g.name)」：\(n) 張（第 \(images.count - n + 1)–\(images.count) 張圖）")
        }
        let prompt = """
        你是旅行分享簡報的編輯。附件圖片依序屬於下面這些主題：
        \(lines.joined(separator: "\n"))

        請用\(language)：
        1. 幫每個主題取一個好記的名字（2–10 個字）。如果原本的名字是地名或日期，保留它，可以加一個短短的描述，例如「京都・紅葉與古寺」。
        2. 幫整份簡報取一個標題（4–12 個字）和一句副標（20 字以內）。
        只輸出 JSON：{"title":"","subtitle":"","groups":[{"id":"G1","name":""}]}
        """
        let reply = try await pi.ask(prompt, images: images)
        guard let json = PiClient.extractJSON(reply) else { throw WanderError(L10n.t("err.aiBadReply")) }
        var names: [UUID: String] = [:]
        for g in json["groups"] as? [[String: Any]] ?? [] {
            guard let id = g["id"] as? String, let idx = Int(id.dropFirst()), idx >= 1, idx <= flat.count,
                  let name = (g["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            names[flat[idx - 1].id] = String(name.prefix(30))
        }
        return Naming(title: (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                      subtitle: (json["subtitle"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                      names: names)
    }

    /// 讓 AI 自己看照片想出幾個主題
    public func proposeThemes(_ list: [PhotoItem], count: ClosedRange<Int> = 3...6) async throws -> [String] {
        var images: [Data] = []
        for p in Self.sample(list.filter { $0.kind == .photo }, 40) { if let d = await thumbnail(p, 320) { images.append(d) } }
        let prompt = """
        附件是一趟旅行裡隨機挑的 \(images.count) 張照片。請用\(language)想出 \(count.lowerBound)–\(count.upperBound) 個主題，
        讓所有照片都能分進其中一個（例如「街頭小吃」「寺廟」「海邊」「旅伴」）。每個主題 2–6 個字，不要重複、不要太籠統。
        只輸出 JSON：{"themes":["",""]}
        """
        let reply = try await pi.ask(prompt, images: images)
        let themes = (PiClient.extractJSON(reply)?["themes"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if themes.isEmpty { throw WanderError(L10n.t("err.aiBadReply")) }
        return Array(themes.prefix(count.upperBound))
    }

    /// 把照片分進指定的主題；分不進去的放「其他」。一次送 30 張。
    public func assign(_ list: [PhotoItem], to themes: [String],
                       progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [PhotoGroup] {
        let other = L10n.t("other")
        var buckets: [String: [String]] = [:]
        let batches = stride(from: 0, to: list.count, by: 30).map { Array(list[$0..<min($0 + 30, list.count)]) }
        for (bi, batch) in batches.enumerated() {
            var images: [Data] = []
            var shown: [PhotoItem] = []
            for p in batch {
                if let d = await thumbnail(p, 320) { images.append(d); shown.append(p) }
                else { buckets[other, default: []].append(p.id) }
            }
            let prompt = """
            附件是 \(images.count) 張照片，依序編號 1 到 \(images.count)。
            主題清單：\(themes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "、"))
            把每張照片分到最適合的一個主題（填主題編號）；真的都不適合就填 0。
            只輸出 JSON：{"assign":{"1":1,"2":3}}
            """
            let reply = try await pi.ask(prompt, images: images)
            let map = PiClient.extractJSON(reply)?["assign"] as? [String: Any] ?? [:]
            for (i, p) in shown.enumerated() {
                let v = (map["\(i + 1)"] as? NSNumber)?.intValue ?? Int("\(map["\(i + 1)"] ?? "0")") ?? 0
                let theme = (1...max(themes.count, 1)).contains(v) && v <= themes.count ? themes[v - 1] : other
                buckets[theme, default: []].append(p.id)
            }
            progress?(bi + 1, batches.count)
        }
        var groups = themes.compactMap { t in buckets[t].map { PhotoGroup(name: t, itemIDs: $0) } }
        if let rest = buckets[other], !themes.contains(other) { groups.append(PhotoGroup(name: other, itemIDs: rest)) }
        return groups
    }
}
