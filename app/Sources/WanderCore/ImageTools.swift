import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 用 Mac 內建的 ImageIO 轉檔：HEIC 也能讀、自動轉正、輸出時不帶任何拍攝資訊（GPS、時間、相機型號）。
public enum ImageTools {
    /// 讀圖並縮到長邊 maxPixel（不放大），已經依 EXIF 方向轉正。
    public static func downscaled(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// 存成 JPEG。只寫像素和色彩設定檔，不寫任何 EXIF／GPS。
    @discardableResult
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { try? FileManager.default.removeItem(at: tmp); return false }
        _ = try? FileManager.default.removeItem(at: url)
        do { try FileManager.default.moveItem(at: tmp, to: url) } catch { return false }
        return true
    }

    public static func makeJPEG(from src: URL, to out: URL, maxPixel: Int, quality: Double) -> Bool {
        guard let img = downscaled(src, maxPixel: maxPixel) else { return false }
        return writeJPEG(img, to: out, quality: quality)
    }

    public static func pixelSize(_ url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orient = p[kCGImagePropertyOrientation] as? Int ?? 1
        return orient >= 5 ? (h, w) : (w, h)
    }

    /// 影片封面：第 0.5 秒的畫面
    public static func videoPoster(_ url: URL, to out: URL, maxPixel: Int) -> Bool {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let sem = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var img: CGImage? }
        let box = Box()
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 0.5, preferredTimescale: 600)) { img, _, _ in
            box.img = img
            sem.signal()
        }
        sem.wait()
        guard let img = box.img else { return false }
        return writeJPEG(img, to: out, quality: 0.8)
    }

    /// 給 AI 看的小縮圖（JPEG data，不帶拍攝資訊）
    public static func aiThumbnail(_ url: URL, maxPixel: Int = 384) -> Data? {
        guard let img = downscaled(url, maxPixel: maxPixel) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
