import AppKit
import Foundation
import Photos

/// 讀「照片」App：拍攝時間、地點、縮圖，以及取出原始檔。
/// 只讀不寫；第一次用會請使用者允許 App 存取照片。
public enum PhotosLibrary {
    public static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    public static func items(for identifiers: [String]) -> [PhotoItem] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byID: [String: PhotoItem] = [:]
        result.enumerateObjects { asset, _, _ in
            let res = PHAssetResource.assetResources(for: asset)
            let name = res.first(where: { $0.type == .photo || $0.type == .video })?.originalFilename
                ?? res.first?.originalFilename ?? "photo.jpg"
            let loc = asset.location.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
            byID[asset.localIdentifier] = PhotoItem(
                id: "photos:" + asset.localIdentifier, assetID: asset.localIdentifier,
                kind: asset.mediaType == .video ? .video : .photo, filename: name,
                date: asset.creationDate, utcOffset: nil, location: loc)
        }
        return identifiers.compactMap { byID[$0] }
    }

    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// 縮圖 JPEG（給 AI 看、給畫面顯示）
    public static func thumbnailData(_ id: String, maxPixel: Int) async -> Data? {
        guard let img = await thumbnail(id, maxPixel: maxPixel),
              let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    public static func thumbnail(_ id: String, maxPixel: Int) async -> NSImage? {
        guard let asset = asset(id) else { return nil }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: maxPixel, height: maxPixel),
                                                  contentMode: .aspectFit, options: opts) { img, _ in
                cont.resume(returning: img)
            }
        }
    }

    /// 把原始檔（HEIC、MOV⋯⋯，有編輯過就用編輯後的版本）寫到資料夾裡
    public static func export(_ item: PhotoItem, to folder: URL) async throws -> URL {
        guard let id = item.assetID, let asset = asset(id) else { throw WanderError("asset missing") }
        let res = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = item.kind == .video ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        guard let r = preferred.lazy.compactMap({ t in res.first { $0.type == t } }).first ?? res.first else {
            throw WanderError("no resource")
        }
        var name = r.originalFilename
        if r.type == .fullSizePhoto || r.type == .fullSizeVideo {
            // 編輯後的版本檔名常是 FullSizeRender：沿用原檔名，副檔名照實際格式
            let orig = res.first { $0.type == .photo || $0.type == .video }?.originalFilename ?? name
            name = (orig as NSString).deletingPathExtension + "." + (name as NSString).pathExtension
        }
        let dest = DeckMaker.uniqueFile(in: folder, name: name)
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: r, toFile: dest, options: opts)
        return dest
    }
}
