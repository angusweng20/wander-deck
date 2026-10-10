import Foundation

/// 檢查 GitHub 上有沒有新版本。只「讀」公開的版本資訊，不送任何使用者資料。
public enum Updates {
    public static let repo = "angusweng20/wander-deck"
    public static var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }

    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    public struct Release: Sendable { public let version: String; public let url: URL }

    public static func latest() async -> Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(v, than: currentVersion) ? Release(version: v, url: page) : nil
    }

    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
