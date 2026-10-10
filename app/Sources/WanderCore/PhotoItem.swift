import AVFoundation
import Foundation
import ImageIO

public struct GeoPoint: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

public enum MediaKind: String, Codable, Sendable { case photo, video }

/// 使用者挑的一張照片或一段影片。可能來自資料夾（fileURL）或「照片」App（assetID）。
public struct PhotoItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var fileURL: URL?
    public var assetID: String?
    public var kind: MediaKind
    public var filename: String
    public var date: Date?
    /// 拍攝地的時差（秒）；EXIF 有寫才有。用來算「當地的哪一天」。
    public var utcOffset: Int?
    public var location: GeoPoint?

    public init(id: String, fileURL: URL? = nil, assetID: String? = nil, kind: MediaKind, filename: String,
                date: Date? = nil, utcOffset: Int? = nil, location: GeoPoint? = nil) {
        self.id = id; self.fileURL = fileURL; self.assetID = assetID; self.kind = kind
        self.filename = filename; self.date = date; self.utcOffset = utcOffset; self.location = location
    }

    /// 當地日期（年、月、日），沒有時間就是 nil
    public var localDay: DateComponents? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utcOffset.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
        return cal.dateComponents([.year, .month, .day, .weekday], from: date)
    }
}

public enum MediaTypes {
    public static let photo: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
    public static let video: Set<String> = ["mov", "mp4", "m4v"]
    public static let audio: Set<String> = ["mp3", "m4a", "aac", "wav"]

    public static func kind(of url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if photo.contains(ext) { return .photo }
        if video.contains(ext) { return .video }
        return nil
    }
}

public enum MetadataReader {
    /// 把資料夾（含子資料夾）或單一檔案展開成照片清單，讀出拍攝時間與 GPS。
    public static func scan(_ urls: [URL], progress: ((Int, Int) -> Void)? = nil) -> [PhotoItem] {
        var files: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let f = en?.nextObject() as? URL {
                    if MediaTypes.kind(of: f) != nil { files.append(f) }
                }
            } else if MediaTypes.kind(of: url) != nil {
                files.append(url)
            }
        }
        var seen = Set<String>()
        files = files.filter { seen.insert($0.standardizedFileURL.path).inserted }
        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var items: [PhotoItem] = []
        for (i, f) in files.enumerated() {
            items.append(read(f))
            progress?(i + 1, files.count)
        }
        return items
    }

    public static func read(_ url: URL) -> PhotoItem {
        let kind = MediaTypes.kind(of: url) ?? .photo
        var item = PhotoItem(id: url.standardizedFileURL.path, fileURL: url, kind: kind, filename: url.lastPathComponent)
        if kind == .photo { readImage(url, into: &item) } else { readVideo(url, into: &item) }
        if item.date == nil {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            item.date = (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date)
        }
        return item
    }

    static func readImage(_ url: URL, into item: inout PhotoItem) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let raw = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff[kCGImagePropertyTIFFDateTime] as? String)
        let offset = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifOffsetTime] as? String)
        if let raw, let (d, off) = parseExifDate(raw, offset: offset) {
            item.date = d
            item.utcOffset = off
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = number(gps[kCGImagePropertyGPSLatitude]), let lon = number(gps[kCGImagePropertyGPSLongitude]) {
            let latSign = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" ? -1.0 : 1.0
            let lonSign = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" ? -1.0 : 1.0
            let p = GeoPoint(lat: lat * latSign, lon: lon * lonSign)
            if abs(p.lat) > 0.0001 || abs(p.lon) > 0.0001 { item.location = p }
        }
    }

    static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    /// "2026:09:24 14:03:11" ＋ "+09:00"
    public static func parseExifDate(_ raw: String, offset: String?) -> (Date, Int?)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var off: Int? = nil
        if let offset, let parsed = parseOffset(offset) {
            off = parsed
            f.timeZone = TimeZone(secondsFromGMT: parsed)
        } else {
            f.timeZone = .current
        }
        guard let d = f.date(from: String(raw.prefix(19))) else { return nil }
        return (d, off)
    }

    static func parseOffset(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 6, let sign = t.first, sign == "+" || sign == "-" else { return nil }
        let parts = t.dropFirst().split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (sign == "-" ? -1 : 1) * (h * 3600 + m * 60)
    }

    static func readVideo(_ url: URL, into item: inout PhotoItem) {
        final class Box: @unchecked Sendable { var date: Date?; var loc: GeoPoint? }
        let box = Box()
        let asset = AVURLAsset(url: url)
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            defer { sem.signal() }
            if let created = try? await asset.load(.creationDate), let d = try? await created.load(.dateValue) {
                box.date = d
            }
            if let meta = try? await asset.load(.metadata) {
                let loc = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .quickTimeMetadataLocationISO6709).first
                    ?? AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierLocation).first
                if let loc, let s = try? await loc.load(.stringValue) { box.loc = parseISO6709(s) }
            }
        }
        sem.wait()
        item.date = box.date
        item.location = box.loc
    }

    /// "+35.0116+135.7681+050.000/"
    public static func parseISO6709(_ s: String) -> GeoPoint? {
        let pattern = #"^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s),
              let lat = Double(s[r1]), let lon = Double(s[r2]) else { return nil }
        return GeoPoint(lat: lat, lon: lon)
    }
}
