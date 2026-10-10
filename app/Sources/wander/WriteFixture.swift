import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 測試用：產生帶拍攝時間、GPS 的 JPEG
enum WriteFixture {
    static func write(_ src: URL, to dest: URL, date: String?, offset: String, lat: Double?, lon: Double?) {
        guard let s = CGImageSourceCreateWithURL(src as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(s, 0, nil),
              let d = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        var props: [CFString: Any] = [:]
        if let date {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: date,
                                                     kCGImagePropertyExifOffsetTimeOriginal: offset]
        }
        if let lat, let lon {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(lat), kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(lon), kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W",
            ]
        }
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        CGImageDestinationFinalize(d)
    }
}
