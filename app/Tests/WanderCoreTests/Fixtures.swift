import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import WanderCore

enum Fixtures {
    static func tempDir(_ name: String = UUID().uuidString) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("wandertest-\(name)")
        try? FileManager.default.removeItem(at: d)
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 畫一張純色的 JPEG，可以帶拍攝時間和 GPS
    static func photo(_ url: URL, w: Int = 800, h: Int = 600, color: (CGFloat, CGFloat, CGFloat) = (0.4, 0.6, 0.8),
                      date: String? = nil, offset: String? = nil, lat: Double? = nil, lon: Double? = nil) {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let img = ctx.makeImage()!
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        var exif: [CFString: Any] = [:]
        if let date { exif[kCGImagePropertyExifDateTimeOriginal] = date }
        if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
        if !exif.isEmpty { props[kCGImagePropertyExifDictionary] = exif }
        if let lat, let lon {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(lat), kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(lon), kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W",
            ]
        }
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        CGImageDestinationFinalize(d)
    }

    static func item(_ id: String, date: Date?, lat: Double? = nil, lon: Double? = nil) -> PhotoItem {
        PhotoItem(id: id, kind: .photo, filename: id, date: date, utcOffset: 9 * 3600,
                  location: lat.map { GeoPoint(lat: $0, lon: lon!) })
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], cwd: URL? = nil) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    static var hasPython: Bool { run("/usr/bin/xcode-select", ["-p"]).0 == 0 }

    static func loadDataJS(_ deck: URL) throws -> [String: Any] {
        let s = try String(contentsOf: deck.appendingPathComponent("_wander/data.js"), encoding: .utf8)
        let start = s.firstIndex(of: "=")!, end = s.lastIndex(of: ";")!
        return try JSONSerialization.jsonObject(with: Data(s[s.index(after: start)..<end].utf8)) as! [String: Any]
    }
}
