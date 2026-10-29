import AVFoundation
import CoreImage
import Photos
import UIKit

enum PhotoLibrary {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func fetchClips(from start: Date, to end: Date, includePhotos: Bool, includeVideos: Bool,
                           favoritesOnly: Bool) -> [Clip] {
        var types: [NSPredicate] = []
        if includePhotos { types.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)) }
        if includeVideos { types.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)) }
        guard !types.isEmpty else { return [] }

        var predicates = [
            NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate),
            NSCompoundPredicate(orPredicateWithSubpredicates: types),
        ]
        if favoritesOnly { predicates.append(NSPredicate(format: "favorite == YES")) }

        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return clips(from: PHAsset.fetchAssets(with: options))
    }

    /// 日ごとの写真・動画の枚数（キーはその日の 0:00）
    static func dailyCounts(from start: Date, to end: Date) -> [Date: Int] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        var counts: [Date: Int] = [:]
        let calendar = Calendar.current
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate, !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        return counts
    }

    static func clips(forIdentifiers ids: [String]) -> [Clip] {
        clips(from: PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
    }

    private static func clips(from result: PHFetchResult<PHAsset>) -> [Clip] {
        var clips: [Clip] = []
        result.enumerateObjects { asset, _, _ in
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            clips.append(Clip(
                assetID: asset.localIdentifier,
                kind: asset.mediaType == .video ? .video : .photo,
                date: asset.creationDate ?? .now,
                duration: asset.mediaType == .video ? asset.duration : 0,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude
            ))
        }
        return clips
    }

    private static let thumbnailManager = PHCachingImageManager()

    static func thumbnail(for assetID: String, side: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return nil
        }
        let scale = await UIScreen.main.scale
        let size = CGSize(width: side * scale, height: side * scale)
        // 一覧のサムネイルは端末内のものを使い、iCloud の帯域を素材の取得に回す。無いときだけ取りに行く。
        if let local = await requestThumbnail(asset, size: size, network: false) { return local }
        return await requestThumbnail(asset, size: size, network: true)
    }

    private static func requestThumbnail(_ asset: PHAsset, size: CGSize, network: Bool) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = network
        return await withCheckedContinuation { continuation in
            thumbnailManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                          options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// 読み込み済みの動画。プレビュー・トリム・書き出しで使い回す（NSCache はスレッドセーフ）
    private static let videoCache = NSCache<NSString, AVAsset>()

    /// 写真ライブラリから受け取った動画ファイルは後で消えることがあるので、ファイルが残っているか確かめる
    static func cachedAVAsset(for assetID: String) -> AVAsset? {
        guard let cached = videoCache.object(forKey: assetID as NSString) else { return nil }
        if let url = (cached as? AVURLAsset)?.url, url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            videoCache.removeObject(forKey: assetID as NSString)
            return nil
        }
        return cached
    }

    /// プレビュー用。iCloud にしかない動画もダウンロードを待たずにストリーミング再生できる。
    static func streamingPlayerItem(for assetID: String) async -> AVPlayerItem? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return nil
        }
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    /// iCloud にしかない場合はダウンロードする。progress は 0...1（別スレッドから呼ばれる）
    /// refresh: true なら保持している動画を使わず写真ライブラリから取り直す
    static func avAsset(for assetID: String, refresh: Bool = false,
                        progress: ((Double) -> Void)? = nil) async throws -> AVAsset {
        if !refresh, let cached = cachedAVAsset(for: assetID) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            throw RenderError.cannotLoad(L("動画が見つかりません"))
        }
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        if let progress {
            options.progressHandler = { value, _, _, _ in progress(value) }
        }
        let avAsset: AVAsset = try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? RenderError.cannotLoad(L("動画を読み込めませんでした")))
                }
            }
        }
        videoCache.setObject(avAsset, forKey: assetID as NSString)
        return avAsset
    }

    /// 書き出しで使うサイズの写真を iCloud から端末に取ってくる（中身は使わない）。
    /// 元データではなく必要なサイズを指定するので、iCloud 上の縮小版で済めばそれだけを取る。
    static func downloadPhoto(_ assetID: String, maxDimension: CGFloat) async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return }
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: maxDimension, height: maxDimension),
                                                  contentMode: .aspectFit,
                                                  options: renderImageOptions) { _, _ in
                continuation.resume()
            }
        }
    }

    /// 書き出し用の写真リクエスト。先読みと同じ条件にして、取得済みのデータを使わせる。
    static var renderImageOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        return options
    }

    /// 書き出しで写真を読み込むときの長辺
    static func renderPhotoDimension(for resolution: OutputResolution) -> CGFloat {
        max(resolution.size.width, resolution.size.height) * 1.25
    }

    /// プレビュー用。端末にある低画質版をすぐ返し、高画質版が届いたら続けて返す。
    static func previewImages(for assetID: String, side: CGFloat) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            let size = CGSize(width: side, height: side)
            let requestID = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                                  options: options) { image, info in
                if let image { continuation.yield(image) }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded || info?[PHImageErrorKey] != nil || (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in PHImageManager.default().cancelImageRequest(requestID) }
        }
    }

    static func saveVideo(at url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

/// 書き出し時に PhotoKit から素材を読み込む
struct PhotoKitMediaProvider: MediaProvider {
    func image(for clip: Clip, maxDimension: CGFloat) async throws -> CIImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [clip.assetID], options: nil).firstObject else {
            throw RenderError.cannotLoad(L("写真が見つかりません"))
        }
        let target = CGSize(width: maxDimension, height: maxDimension)
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit,
                                                  options: PhotoLibrary.renderImageOptions) { image, info in
                if let image, let cgImage = image.cgImage {
                    continuation.resume(returning: CIImage(cgImage: cgImage)
                        .oriented(CGImagePropertyOrientation(image.imageOrientation)))
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? RenderError.cannotLoad(L("写真を読み込めませんでした")))
                }
            }
        }
    }

    func asset(for clip: Clip, refresh: Bool) async throws -> AVAsset {
        try await PhotoLibrary.avAsset(for: clip.assetID, refresh: refresh)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
