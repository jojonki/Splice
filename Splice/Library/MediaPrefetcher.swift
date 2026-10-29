import CoreGraphics
import Foundation
import Observation

/// ムービー内の素材を裏で iCloud から端末へダウンロードしておく。
/// プレビューや書き出しのときに待たされないようにするためのもの。
/// 大きな動画が写真を待たせないよう、写真と動画で別々に同時実行数を持つ。
@MainActor
@Observable
final class MediaPrefetcher {
    static let shared = MediaPrefetcher()

    /// 取得待ち＋取得中の件数
    private(set) var remaining = 0

    @ObservationIgnored private var photoQueue: [String] = []
    @ObservationIgnored private var videoQueue: [String] = []
    @ObservationIgnored private var photosInFlight: Set<String> = []
    @ObservationIgnored private var videosInFlight: Set<String> = []
    @ObservationIgnored private var finished: Set<String> = []
    @ObservationIgnored private var photoDimension: CGFloat = 2400
    private let maxPhotos = 6
    private let maxVideos = 2

    func prefetch(_ clips: [Clip], resolution: OutputResolution) {
        photoDimension = PhotoLibrary.renderPhotoDimension(for: resolution)
        let known = finished.union(photosInFlight).union(videosInFlight)
            .union(photoQueue).union(videoQueue)
        for clip in clips where !known.contains(clip.assetID) {
            switch clip.kind {
            case .photo: photoQueue.append(clip.assetID)
            case .video: videoQueue.append(clip.assetID)
            }
        }
        pump()
    }

    /// プレビューで開いた素材などを先頭に回す
    func prioritize(_ clips: [Clip]) {
        for clip in clips.reversed() {
            switch clip.kind {
            case .photo:
                if let i = photoQueue.firstIndex(of: clip.assetID) { photoQueue.insert(photoQueue.remove(at: i), at: 0) }
            case .video:
                if let i = videoQueue.firstIndex(of: clip.assetID) { videoQueue.insert(videoQueue.remove(at: i), at: 0) }
            }
        }
    }

    private func pump() {
        while photosInFlight.count < maxPhotos, !photoQueue.isEmpty {
            let id = photoQueue.removeFirst()
            photosInFlight.insert(id)
            let dimension = photoDimension
            Task {
                await PhotoLibrary.downloadPhoto(id, maxDimension: dimension)
                photosInFlight.remove(id)
                finish(id)
            }
        }
        while videosInFlight.count < maxVideos, !videoQueue.isEmpty {
            let id = videoQueue.removeFirst()
            videosInFlight.insert(id)
            Task {
                _ = try? await PhotoLibrary.avAsset(for: id)
                videosInFlight.remove(id)
                finish(id)
            }
        }
        remaining = photoQueue.count + videoQueue.count + photosInFlight.count + videosInFlight.count
    }

    /// 失敗しても再試行はしない。実際に使うときにもう一度取りに行く。
    private func finish(_ id: String) {
        finished.insert(id)
        pump()
    }
}
