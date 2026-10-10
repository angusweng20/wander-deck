import Foundation

/// 一個主題（之後變成簡報裡的一個資料夾）。可以再有一層子主題。
public struct PhotoGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var itemIDs: [String]
    public var children: [PhotoGroup]
    public var countryCode: String?

    public init(id: UUID = UUID(), name: String, itemIDs: [String] = [], children: [PhotoGroup] = [],
                countryCode: String? = nil) {
        self.id = id; self.name = name; self.itemIDs = itemIDs; self.children = children
        self.countryCode = countryCode
    }

    public var allItemIDs: [String] { itemIDs + children.flatMap(\.allItemIDs) }
    public var count: Int { allItemIDs.count }
}

public enum GroupMode: String, Codable, CaseIterable, Sendable {
    case place, date, manual
}

public enum Grouping {
    // MARK: 依日期

    public static func byDate(_ items: [PhotoItem]) -> [PhotoGroup] {
        let fmt = DateFormatter()
        fmt.locale = L10n.locale
        fmt.setLocalizedDateFormatFromTemplate(L10n.isEnglish ? "EEE MMM d" : "MMMdEEE")
        var days: [String: (date: Date, ids: [String], label: String)] = [:]
        var undated: [String] = []
        for it in items.sorted(by: earlier) {
            guard let day = it.localDay, let date = it.date else { undated.append(it.id); continue }
            let key = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
            if days[key] == nil {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = it.utcOffset.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
                fmt.timeZone = cal.timeZone
                days[key] = (date, [], fmt.string(from: date))
            }
            days[key]!.ids.append(it.id)
        }
        var groups = days.keys.sorted().map { PhotoGroup(name: days[$0]!.label, itemIDs: days[$0]!.ids) }
        if !undated.isEmpty { groups.append(PhotoGroup(name: L10n.t("unsorted"), itemIDs: undated)) }
        return groups
    }

    // MARK: 依地點（國家 → 城市）

    /// 沒有 GPS 的照片：用前後 3 小時內最近一張有 GPS 的照片位置
    public static func fillMissingLocations(_ items: [PhotoItem], window: TimeInterval = 3 * 3600) -> [String: GeoPoint] {
        let located = items.filter { $0.location != nil && $0.date != nil }.sorted(by: earlier)
        var result: [String: GeoPoint] = [:]
        for it in items {
            if let loc = it.location { result[it.id] = loc; continue }
            guard let d = it.date else { continue }
            var best: (TimeInterval, GeoPoint)?
            for l in located {
                let gap = abs(l.date!.timeIntervalSince(d))
                if gap <= window, gap < (best?.0 ?? .infinity) { best = (gap, l.location!) }
            }
            if let best { result[it.id] = best.1 }
        }
        return result
    }

    /// 約 10 公里內算同一格，每格只查一次地名
    static func cellKey(_ p: GeoPoint) -> String {
        String(format: "%.1f,%.1f", (p.lat * 10).rounded() / 10, (p.lon * 10).rounded() / 10)
    }

    public static func byPlace(_ items: [PhotoItem], lookup: PlaceLookup,
                               progress: ((Int, Int) -> Void)? = nil) async -> [PhotoGroup] {
        let points = fillMissingLocations(items)
        var cellPoint: [String: GeoPoint] = [:]
        for it in items.sorted(by: earlier) {
            if let p = points[it.id], cellPoint[cellKey(p)] == nil { cellPoint[cellKey(p)] = p }
        }
        var cellPlace: [String: Place] = [:]
        let keys = cellPoint.keys.sorted()
        for (i, k) in keys.enumerated() {
            if let place = try? await lookup.place(for: cellPoint[k]!) { cellPlace[k] = place }
            progress?(i + 1, keys.count)
        }

        struct Bucket { var country: String; var code: String?; var cities: [String: [PhotoItem]] = [:] }
        var countries: [String: Bucket] = [:]
        var unsorted: [String] = []
        for it in items.sorted(by: earlier) {
            guard let p = points[it.id], let place = cellPlace[cellKey(p)],
                  place.country != nil || place.city != nil else { unsorted.append(it.id); continue }
            let country = place.country ?? L10n.t("otherPlaces")
            let city = place.city ?? place.country ?? L10n.t("otherPlaces")
            countries[country, default: Bucket(country: country, code: place.countryCode)].cities[city, default: []].append(it)
        }

        func first(_ list: [PhotoItem]) -> Date { list.compactMap(\.date).min() ?? .distantFuture }
        func cityGroups(_ b: Bucket) -> [PhotoGroup] {
            b.cities.sorted { first($0.value) < first($1.value) }
                .map { PhotoGroup(name: $0.key, itemIDs: $0.value.map(\.id), countryCode: b.code) }
        }
        let ordered = countries.values.sorted {
            first($0.cities.values.flatMap { $0 }) < first($1.cities.values.flatMap { $0 })
        }
        var groups: [PhotoGroup]
        if ordered.count == 1 {
            groups = cityGroups(ordered[0])              // 只去一個國家：直接用城市當主題
        } else {
            groups = ordered.map { b in
                let cities = cityGroups(b)
                return cities.count == 1
                    ? PhotoGroup(name: b.country, itemIDs: cities[0].itemIDs, countryCode: b.code)
                    : PhotoGroup(name: b.country, children: cities, countryCode: b.code)
            }
        }
        if !unsorted.isEmpty { groups.append(PhotoGroup(name: L10n.t("unsorted"), itemIDs: unsorted)) }
        return groups
    }

    /// 照片最多的國家（拿來挑風格包）
    public static func dominantCountry(_ groups: [PhotoGroup]) -> String? {
        var count: [String: Int] = [:]
        func walk(_ g: PhotoGroup) {
            if let c = g.countryCode { count[c, default: 0] += g.itemIDs.count }
            g.children.forEach(walk)
        }
        groups.forEach(walk)
        return count.max { $0.value < $1.value }?.key
    }

    static func earlier(_ a: PhotoItem, _ b: PhotoItem) -> Bool {
        (a.date ?? .distantFuture, a.filename) < (b.date ?? .distantFuture, b.filename)
    }

    /// 資料夾名稱不能有 / 和 :，前後空白也拿掉
    public static func safeName(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "/", with: "／").replacingOccurrences(of: ":", with: "：")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let noDot = cleaned.hasPrefix(".") || cleaned.hasPrefix("_") ? String(cleaned.dropFirst()) : cleaned
        return noDot.isEmpty ? "untitled" : String(noDot.prefix(60))
    }
}
