import AVFoundation
import CoreImage

protocol MediaProvider {
    func image(for clip: Clip, maxDimension: CGFloat) async throws -> CIImage
    func asset(for clip: Clip, refresh: Bool) async throws -> AVAsset
}

enum RenderError: LocalizedError {
    case cannotLoad(String)
    case writerFailed(String)
    case nothingToRender

    var errorDescription: String? {
        switch self {
        case let .cannotLoad(message), let .writerFailed(message): message
        case .nothingToRender: L("書き出す素材がありません")
        }
    }
}

/// タイムラインを1フレームずつ Core Image で合成し、AVAssetWriter で mp4 に書き出す
final class VideoRenderer {
    static let fps: Int32 = 30
    /// 写真のゆっくりズーム（Ken Burns）の最大倍率
    private static let maxZoom: CGFloat = 1.06
    private static let overlayFade = 0.4

    let timeline: Timeline
    private let project: Project
    private let provider: MediaProvider
    private let outputURL: URL
    private let size: CGSize
    private var rect: CGRect { CGRect(origin: .zero, size: size) }
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let overlayImages: OverlayImageCache
    private var overlays: [(kind: OverlayKind, start: Double, end: Double)] = []

    private enum Prepared {
        case card(CIImage)
        case still(foreground: CIImage, background: CIImage?)
        case video(VideoFrameReader)
    }

    private var assets: [UUID: AVAsset] = [:]
    private var prepared: [Int: Prepared] = [:]

    private var audioReader: AVAssetReader?
    private var audioOutput: AVAssetReaderOutput?
    private var audioInput: AVAssetWriterInput?
    private var pendingAudio: CMSampleBuffer?
    private var audioFinished = true

    init(project: Project, provider: MediaProvider, outputURL: URL) {
        self.project = project
        self.provider = provider
        self.outputURL = outputURL
        timeline = Timeline(project: project)
        size = project.settings.resolution.size
        overlayImages = OverlayImageCache(size: size)

        for item in timeline.items {
            if let title = item.chapterTitle {
                let start = item.start + item.fadeIn * 0.5
                let end = item.start + min(item.duration - item.fadeOut, 3.5)
                if end > start { overlays.append((.chapter(title), start, end)) }
            }
            if case let .clip(clip) = item.content {
                if !clip.caption.isEmpty {
                    overlays.append((.caption(clip.caption), item.start + item.fadeIn, item.end - item.fadeOut))
                }
                if clip.showsTimestamp {
                    overlays.append((.timestamp(clip.timestampText), item.start + item.fadeIn, item.end - item.fadeOut))
                }
            }
        }
    }

    /// progress は 0...1。キャンセルは Task のキャンセルで行う。
    func render(progress: @escaping (Double) -> Void) async throws {
        let items = timeline.items
        guard timeline.duration > 0 else { throw RenderError.nothingToRender }
        try? FileManager.default.removeItem(at: outputURL)

        // 1. 動画素材の読み込み（iCloud からのダウンロードを含む）
        let videoClips = items.compactMap { item -> Clip? in
            if case let .clip(clip) = item.content, clip.kind == .video { return clip }
            return nil
        }
        for (n, clip) in videoClips.enumerated() {
            try Task.checkCancellation()
            // 保持している動画はファイルが消えていることがあるので、書き出しでは取り直す
            assets[clip.id] = try await describingFailure(of: clip) { try await provider.asset(for: clip, refresh: true) }
            progress(0.1 * Double(n + 1) / Double(videoClips.count))
        }

        // 2. 書き出し準備
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: project.settings.resolution.bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: Self.fps,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        writer.add(videoInput)

        if project.settings.keepAudio, let (composition, mix) = try await makeAudioComposition() {
            let reader = try AVAssetReader(asset: composition)
            let output = AVAssetReaderAudioMixOutput(audioTracks: composition.tracks(withMediaType: .audio),
                                                     audioSettings: [
                                                         AVFormatIDKey: kAudioFormatLinearPCM,
                                                         AVSampleRateKey: 48_000,
                                                         AVNumberOfChannelsKey: 2,
                                                         AVLinearPCMBitDepthKey: 16,
                                                         AVLinearPCMIsFloatKey: false,
                                                         AVLinearPCMIsBigEndianKey: false,
                                                         AVLinearPCMIsNonInterleaved: false,
                                                     ])
            output.audioMix = mix
            reader.add(output)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            if reader.startReading() {
                audioReader = reader
                audioOutput = output
                audioInput = input
                audioFinished = false
            }
        }

        guard writer.startWriting() else {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? L("書き出しを開始できません"))
        }
        writer.startSession(atSourceTime: .zero)

        // 3. フレームごとに合成
        do {
            let frameCount = Int((timeline.duration * Double(Self.fps)).rounded(.up))
            var firstActive = 0
            for frame in 0 ..< frameCount {
                try Task.checkCancellation()
                let t = Double(frame) / Double(Self.fps)

                while firstActive < items.count, items[firstActive].end <= t {
                    release(firstActive)
                    firstActive += 1
                }
                var active: [Int] = []
                var i = firstActive
                while i < items.count, items[i].start <= t {
                    if items[i].end > t {
                        if prepared[i] == nil { prepared[i] = try await prepare(i) }
                        active.append(i)
                    }
                    i += 1
                }

                while !videoInput.isReadyForMoreMediaData {
                    if writer.status == .failed { break }
                    pumpAudio(upTo: t + 1)
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                if writer.status == .failed {
                    throw RenderError.writerFailed(writer.error?.localizedDescription ?? L("書き出しに失敗しました"))
                }

                try autoreleasepool {
                    let image = compose(at: t, active: active)
                    guard let pool = adaptor.pixelBufferPool else {
                        throw RenderError.writerFailed(L("バッファを確保できません"))
                    }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    guard let buffer else { throw RenderError.writerFailed(L("バッファを確保できません")) }
                    context.render(image, to: buffer, bounds: rect, colorSpace: CGColorSpace(name: CGColorSpace.itur_709))
                    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: Self.fps))
                }
                pumpAudio(upTo: t)
                if frame % 10 == 0 { progress(0.1 + 0.9 * Double(frame) / Double(frameCount)) }
            }

            videoInput.markAsFinished()
            while !audioFinished {
                try Task.checkCancellation()
                pumpAudio(upTo: .infinity)
                if !audioFinished { try await Task.sleep(nanoseconds: 2_000_000) }
            }
            for index in Array(prepared.keys) { release(index) }
            await writer.finishWriting()
            if writer.status != .completed {
                throw RenderError.writerFailed(writer.error?.localizedDescription ?? L("書き出しに失敗しました"))
            }
            progress(1)
        } catch {
            for index in Array(prepared.keys) { release(index) }
            audioReader?.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    // MARK: - 映像

    private func prepare(_ index: Int) async throws -> Prepared {
        let item = timeline.items[index]
        switch item.content {
        case let .titleCard(title, subtitle):
            return .card(overlayImages.image(for: .titleCard(title: title, subtitle: subtitle)))

        case let .clip(clip) where clip.kind == .photo:
            let dimension = PhotoLibrary.renderPhotoDimension(for: project.settings.resolution)
            let raw = try await describingFailure(of: clip) { try await provider.image(for: clip, maxDimension: dimension) }
            let image = raw.transformed(by: CGAffineTransform(translationX: -raw.extent.minX, y: -raw.extent.minY))
            // 最大ズーム時の大きさで一度ラスタライズしておき、毎フレームは縮小だけにする
            let scale = fitScale(for: image.extent.size) * Self.maxZoom
            let foreground = rasterize(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
            let background = covers(image.extent.size) ? nil : rasterize(blurredBackground(of: image))
            return .still(foreground: foreground, background: background)

        case let .clip(clip):
            return try await describingFailure(of: clip) {
                if let asset = assets[clip.id],
                   let reader = try? await VideoFrameReader(asset: asset, start: clip.trimStart, duration: item.duration) {
                    return .video(reader)
                }
                // 読めなければ一度だけ取り直して再試行
                let fresh = try await provider.asset(for: clip, refresh: true)
                assets[clip.id] = fresh
                return .video(try await VideoFrameReader(asset: fresh, start: clip.trimStart, duration: item.duration))
            }
        }
    }

    /// どの素材で失敗したか分かるエラーにする
    private func describingFailure<T>(of clip: Clip, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let kind = clip.kind == .video ? L("動画") : L("写真")
            let date = clip.date.formatted(inApp: .dateTime.month().day().hour().minute())
            throw RenderError.cannotLoad(L("%@撮影の%@を読み込めませんでした。\n%@", date, kind, error.localizedDescription))
        }
    }

    private func release(_ index: Int) {
        if case let .video(reader) = prepared[index] { reader.cancel() }
        prepared[index] = nil
    }

    private func compose(at t: Double, active: [Int]) -> CIImage {
        let items = timeline.items
        var canvas = CIImage(color: .black).cropped(to: rect)
        for index in active {
            let item = items[index]
            let local = t - item.start
            guard let layer = layer(for: index, localTime: local) else { continue }
            var alpha = item.fadeIn > 0 ? min(1, local / item.fadeIn) : 1
            if index == items.count - 1, item.fadeOut > 0 {
                alpha = min(alpha, (item.end - t) / item.fadeOut)
            }
            canvas = layer.cropped(to: rect).withAlpha(alpha).composited(over: canvas)
        }
        for overlay in overlays where overlay.start <= t && t < overlay.end {
            let alpha = min(1, (t - overlay.start) / Self.overlayFade, (overlay.end - t) / Self.overlayFade)
            canvas = overlayImages.image(for: overlay.kind).withAlpha(alpha).composited(over: canvas)
        }
        return canvas.cropped(to: rect)
    }

    private func layer(for index: Int, localTime: Double) -> CIImage? {
        switch prepared[index] {
        case let .card(image):
            return image
        case let .still(foreground, background):
            let progress = localTime / timeline.items[index].duration
            let zoom = 1 + (Self.maxZoom - 1) * CGFloat(progress)
            let image = centered(foreground, scale: zoom / Self.maxZoom)
            return background.map { image.composited(over: $0) } ?? image
        case let .video(reader):
            guard let frame = reader.frame(at: localTime) else { return nil }
            let image = centered(frame, scale: fitScale(for: frame.extent.size))
            return covers(frame.extent.size) ? image : image.composited(over: blurredBackground(of: frame))
        case nil:
            return nil
        }
    }

    private func fitScale(for imageSize: CGSize) -> CGFloat {
        min(size.width / imageSize.width, size.height / imageSize.height)
    }

    /// アスペクト比がほぼ同じで画面全体を覆うか
    private func covers(_ imageSize: CGSize) -> Bool {
        let scale = fitScale(for: imageSize)
        return imageSize.width * scale >= size.width - 2 && imageSize.height * scale >= size.height - 2
    }

    private func centered(_ image: CIImage, scale: CGFloat) -> CIImage {
        let e = image.extent
        let transform = CGAffineTransform(translationX: -e.minX, y: -e.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (size.width - e.width * scale) / 2,
                                             y: (size.height - e.height * scale) / 2))
        return image.transformed(by: transform)
    }

    /// 縦長素材の左右を埋める、ぼかして暗くした背景。1/8 に縮小してからぼかして軽くする。
    private func blurredBackground(of image: CIImage) -> CIImage {
        let k: CGFloat = 8
        let small = CGSize(width: size.width / k, height: size.height / k)
        let e = image.extent
        let scale = max(small.width / e.width, small.height / e.height)
        let transform = CGAffineTransform(translationX: -e.minX, y: -e.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (small.width - e.width * scale) / 2,
                                             y: (small.height - e.height * scale) / 2))
        return image.transformed(by: transform)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 4)
            .transformed(by: CGAffineTransform(scaleX: k, y: k))
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.2])
            .cropped(to: rect)
    }

    private func rasterize(_ image: CIImage) -> CIImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return image }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
    }

    // MARK: - 音声

    /// 動画の音声を2本のトラックに交互に並べ、映像と同じタイミングでフェードさせる
    private func makeAudioComposition() async throws -> (AVComposition, AVAudioMix)? {
        let composition = AVMutableComposition()
        var lanes: [(track: AVMutableCompositionTrack, params: AVMutableAudioMixInputParameters, end: CMTime)] = []

        for item in timeline.items {
            guard case let .clip(clip) = item.content, clip.kind == .video, let asset = assets[clip.id],
                  let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let sourceRange = try await source.load(.timeRange)
            let sourceStart = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
            let duration = CMTimeMinimum(CMTime(seconds: item.duration, preferredTimescale: 600),
                                         sourceRange.end - sourceStart)
            guard duration > .zero else { continue }
            let at = CMTime(seconds: item.start, preferredTimescale: 600)

            let lane: Int
            if let free = lanes.firstIndex(where: { $0.end <= at }) {
                lane = free
            } else if let track = composition.addMutableTrack(withMediaType: .audio,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid) {
                lanes.append((track, AVMutableAudioMixInputParameters(track: track), .zero))
                lane = lanes.count - 1
            } else {
                continue
            }

            let track = lanes[lane].track
            if lanes[lane].end < at {
                track.insertEmptyTimeRange(CMTimeRange(start: lanes[lane].end, end: at))
            }
            try track.insertTimeRange(CMTimeRange(start: sourceStart, duration: duration), of: source, at: at)

            let fadeIn = CMTime(seconds: item.fadeIn, preferredTimescale: 600)
            let fadeOut = CMTime(seconds: item.fadeOut, preferredTimescale: 600)
            let params = lanes[lane].params
            if fadeIn > .zero {
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: at, duration: fadeIn))
            }
            if fadeOut > .zero {
                let fadeOutStart = CMTimeMaximum(at + fadeIn, at + duration - fadeOut)
                params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0,
                                     timeRange: CMTimeRange(start: fadeOutStart, duration: fadeOut))
            }
            lanes[lane].end = at + duration
        }

        guard !lanes.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = lanes.map(\.params)
        return (composition, mix)
    }

    private func pumpAudio(upTo time: Double) {
        guard let input = audioInput, let output = audioOutput, !audioFinished else { return }
        while input.isReadyForMoreMediaData {
            if pendingAudio == nil { pendingAudio = output.copyNextSampleBuffer() }
            guard let buffer = pendingAudio else {
                input.markAsFinished()
                audioFinished = true
                return
            }
            if CMSampleBufferGetPresentationTimeStamp(buffer).seconds > time { return }
            input.append(buffer)
            pendingAudio = nil
        }
    }
}

extension CIImage {
    func withAlpha(_ alpha: Double) -> CIImage {
        guard alpha < 0.999 else { return self }
        return applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, alpha))),
        ])
    }
}
