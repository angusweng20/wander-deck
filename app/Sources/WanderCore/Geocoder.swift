import CoreLocation
import Foundation
import MapKit

/// 一個地點的名稱：國家、城市。
public struct Place: Codable, Hashable, Sendable {
    public var countryCode: String?    // "JP"
    public var country: String?        // 「日本」
    public var city: String?           // 「京都市」
    public init(countryCode: String?, country: String?, city: String?) {
        self.countryCode = countryCode; self.country = country; self.city = city
    }
}

public protocol PlaceLookup: Sendable {
    func place(for point: GeoPoint) async throws -> Place
}

/// 用 Apple 地圖把座標換成國家、城市名稱。結果存在快取裡，同一個地方不會重問。
/// 只會送出座標（不送照片），而且附近的照片只問一次。
public actor AppleGeocoder: PlaceLookup {
    private var cache: [String: Place] = [:]
    private let cacheFile: URL
    private let localeID: String

    public init(localeIdentifier: String = L10n.isEnglish ? "en_US" : "zh_Hant_TW") {
        localeID = localeIdentifier
        cacheFile = Paths.caches.appendingPathComponent("places-\(localeIdentifier).json")
        if let data = try? Data(contentsOf: cacheFile),
           let saved = try? JSONDecoder().decode([String: Place].self, from: data) {
            cache = saved
        }
    }

    /// 約 1 公里內算同一個地方
    static func key(_ p: GeoPoint) -> String { String(format: "%.2f,%.2f", p.lat, p.lon) }

    public func place(for point: GeoPoint) async throws -> Place {
        let k = Self.key(point)
        if let hit = cache[k] { return hit }
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let p = try await lookup(point)
                cache[k] = p
                save()
                return p
            } catch {
                lastError = error
                // Apple 有查詢頻率限制：被擋就等一下再試
                try? await Task.sleep(nanoseconds: UInt64(1_500_000_000 * (attempt + 1)))
            }
        }
        throw lastError ?? WanderError("geocode failed")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheFile, options: .atomic) }
    }

    private func lookup(_ point: GeoPoint) async throws -> Place {
        let loc = CLLocation(latitude: point.lat, longitude: point.lon)
        let locale = Locale(identifier: localeID)
        // CLGeocoder 給的層級比較完整（東京、臺北市這種「市」那一層拿得到）；
        // 它在 macOS 26 標成過時但還能用，萬一失效就改用 MapKit 的新寫法。
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: locale)
            if let m = marks.first {
                return Place(countryCode: m.isoCountryCode, country: m.country,
                             city: Self.cityName(iso: m.isoCountryCode, admin: m.administrativeArea,
                                                 subAdmin: m.subAdministrativeArea, locality: m.locality))
            }
        } catch {
            if #unavailable(macOS 26.0) { throw error }
        }
        if #available(macOS 26.0, *) {
            guard let req = MKReverseGeocodingRequest(location: loc) else { throw WanderError("bad location") }
            req.preferredLocale = locale
            let items = try await req.mapItems
            guard let rep = items.first?.addressRepresentations else { return Place(countryCode: nil, country: nil, city: nil) }
            return Place(countryCode: rep.region?.identifier, country: rep.regionName, city: rep.cityName)
        }
        throw WanderError("geocode failed")
    }

    /// 挑「城市」那一層：東京的區、台灣的區都往上收到市；香港、澳門、新加坡整個算一個城市
    public static func cityName(iso: String?, admin: String?, subAdmin: String?, locality: String?) -> String? {
        let en = !(admin ?? locality ?? "").unicodeScalars.contains { $0.value > 0x2E80 }
        switch iso {
        case "HK": return en ? "Hong Kong" : "香港"
        case "MO": return en ? "Macau" : "澳門"
        case "SG": return en ? "Singapore" : "新加坡"
        case "JP" where ["東京", "東京都", "Tokyo"].contains(admin ?? ""):
            return en ? "Tokyo" : "東京"
        default: break
        }
        if let l = locality, !l.isEmpty {
            let isDistrict = l.hasSuffix("區") || l.hasSuffix("区") || l.hasSuffix(" District") || l.hasSuffix("-ku")
            if isDistrict, let up = subAdmin ?? admin, !up.isEmpty { return up }
            return l
        }
        return subAdmin ?? admin
    }
}
