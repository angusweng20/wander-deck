import AppKit
import SwiftUI
import WanderCore

/// 畫面上的小縮圖（記在記憶體裡，捲來捲去不會重算）
actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 3000 }

    func image(for item: PhotoItem, size: Int = 220) async -> NSImage? {
        let key = "\(item.id)#\(size)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        var img: NSImage?
        if let url = item.fileURL {
            img = await Task.detached(priority: .utility) { () -> NSImage? in
                if item.kind == .video {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wd-\(UUID().uuidString).jpg")
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    guard ImageTools.videoPoster(url, to: tmp, maxPixel: size) else { return nil }
                    return NSImage(contentsOf: tmp)
                }
                guard let cg = ImageTools.downscaled(url, maxPixel: size) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
        } else if let id = item.assetID {
            img = await PhotosLibrary.thumbnail(id, maxPixel: size)
        }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}

struct Thumbnail: View {
    let item: PhotoItem
    var selected = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottomLeading) {
            if item.kind == .video {
                Image(systemName: "video.fill").font(.caption).foregroundStyle(.white)
                    .padding(5).shadow(radius: 2)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? Color.brand : .clear, lineWidth: 3)
        }
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.brand)
                    .font(.title3).padding(4)
            }
        }
        .task(id: item.id) { image = await ThumbnailCache.shared.image(for: item) }
    }
}
