import AVFoundation
import CoreImage

/// 動画のフレームを先頭から順に取り出す。向きの補正と HDR→SDR 変換は AVVideoComposition に任せる。
final class VideoFrameReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput
    private let start: Double
    private var current: CMSampleBuffer?
    private var next: CMSampleBuffer?

    init(asset: AVAsset, start: Double, duration: Double) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw RenderError.cannotLoad(L("映像トラックがありません")) }

        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = composition
        output.alwaysCopiesSampleData = false
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: duration, preferredTimescale: 600))
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? RenderError.cannotLoad(L("動画を読み込めませんでした"))
        }
        self.start = start
    }

    /// クリップ先頭からの経過秒に対応するフレーム。末尾を過ぎたら最後のフレームを返し続ける。
    func frame(at localTime: Double) -> CIImage? {
        let target = start + localTime + 0.001
        while true {
            if next == nil { next = output.copyNextSampleBuffer() }
            guard let candidate = next else { break }
            if current == nil || CMSampleBufferGetPresentationTimeStamp(candidate).seconds <= target {
                current = candidate
                next = nil
            } else {
                break
            }
        }
        guard let current, let pixelBuffer = CMSampleBufferGetImageBuffer(current) else { return nil }
        return CIImage(cvPixelBuffer: pixelBuffer)
    }

    func cancel() {
        reader.cancelReading()
    }
}
