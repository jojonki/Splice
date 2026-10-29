import AVFoundation
import SwiftUI

/// 素材1件のプレビュー。動画は使う範囲をループ再生し、トリムバーで範囲を直せる。
/// 変更は画面を離れるとき（左右移動・閉じる）に onSave で保存する。
struct ClipDetailView: View {
    let clip: Clip
    var onSave: (Clip) -> Void
    var onRemove: () -> Void
    /// プレビュー部分を左右にスワイプしたとき（-1: 前へ, +1: 次へ）
    var onSwipe: (Int) -> Void

    @State private var caption: String
    @State private var showsTimestamp: Bool
    @State private var start: Double
    @State private var end: Double
    @State private var isRemoved = false
    @State private var playback = PreviewPlayer()
    @State private var frames: [UIImage] = []
    @State private var image: UIImage?

    init(clip: Clip, onSave: @escaping (Clip) -> Void, onRemove: @escaping () -> Void,
         onSwipe: @escaping (Int) -> Void) {
        self.clip = clip
        self.onSave = onSave
        self.onRemove = onRemove
        self.onSwipe = onSwipe
        _caption = State(initialValue: clip.caption)
        _showsTimestamp = State(initialValue: clip.showsTimestamp)
        _start = State(initialValue: clip.trimStart)
        _end = State(initialValue: clip.trimEnd ?? clip.duration)
    }

    /// 実際に読み込んだ動画の長さ（スローモーションなどで PHAsset の値とずれることがある）
    private var duration: Double { playback.duration ?? clip.duration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                preview
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        onSwipe(value.translation.width < 0 ? 1 : -1)
                    })
                if clip.kind == .video { trimControls }
                VStack(alignment: .leading, spacing: 6) {
                    Text("キャプション").font(.subheadline).foregroundStyle(.secondary)
                    TextField("例：伏見稲荷の千本鳥居", text: $caption)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle(isOn: $showsTimestamp) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("撮影日時を表示")
                        Text(clip.timestampText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 6) {
                    Button(role: .destructive) {
                        isRemoved = true
                        onRemove()
                    } label: {
                        Label("ムービーから外す", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Text("写真ライブラリからは削除されません")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .task(id: playback.duration) { await videoDidLoad() }
        .onChange(of: start) { playback.loopStart = start }
        .onChange(of: end) { playback.loopEnd = end }
        .onDisappear {
            playback.close()
            guard !isRemoved else { return }
            var edited = clip
            edited.caption = caption.trimmingCharacters(in: .whitespaces)
            edited.showsTimestamp = showsTimestamp
            if clip.kind == .video {
                edited.duration = duration
                edited.trimStart = start < 0.05 ? 0 : start
                edited.trimEnd = end >= duration - 0.05 ? nil : min(end, duration)
            }
            onSave(edited)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if clip.kind == .video {
            PlayerLayerView(player: playback.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if let progress = playback.downloadProgress {
                        VStack(spacing: 8) {
                            ProgressView(value: progress).frame(width: 160).tint(.white)
                            Text(L("iCloudからダウンロード中 %lld%%", Int(progress * 100)))
                                .font(.caption).foregroundStyle(.white)
                        }
                    } else if playback.player.currentItem == nil {
                        ProgressView().tint(.white)
                    } else if !playback.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }
                .onTapGesture { playback.togglePlay() }
        } else {
            Color.black
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var trimControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(formatPrecise(start))
                Spacer()
                Text(L("%@ を使用", formatPrecise(end - start)))
                    .bold()
                    .foregroundStyle(end - start < duration - 0.05 ? Color.yellow : .primary)
                Spacer()
                Text(formatPrecise(end))
            }
            .font(.caption.monospacedDigit())

            TrimTimeline(duration: duration, frames: frames, start: $start, end: $end,
                         playhead: playback.currentTime,
                         onScrub: { time in playback.scrub(to: time) },
                         onScrubEnd: { isStart in
                             // 開始側は頭から、終了側は終わりの直前から再生して確認しやすくする
                             playback.endScrub(playFrom: isStart ? start : max(start, end - 2))
                         },
                         onSeek: { time in playback.seekScrub(to: time) },
                         onSeekEnd: { playback.endSeekScrub() })
                .padding(.top, 8)

            HStack {
                Text(L("全体 %@", formatPrecise(duration)))
                Spacer()
                if start > 0.05 || end < duration - 0.05 {
                    Button("リセット") {
                        start = 0
                        end = duration
                        playback.seek(to: 0)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        if clip.kind == .video {
            playback.loopStart = start
            playback.loopEnd = end
            await playback.load(assetID: clip.assetID)
        } else {
            for await preview in PhotoLibrary.previewImages(for: clip.assetID, side: 2000) {
                image = preview
            }
        }
    }

    /// 動画の読み込みが終わったら、実際の長さに範囲を合わせてトリムバーのコマを作る
    private func videoDidLoad() async {
        guard let asset = playback.asset, playback.duration != nil else { return }
        if end > duration || clip.trimEnd == nil { end = duration }
        start = min(start, max(0, end - 1))
        frames = await filmstripFrames(of: asset)
    }

    private func filmstripFrames(of asset: AVAsset, count: Int = 10) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var images: [UIImage] = []
        for i in 0 ..< count {
            guard !Task.isCancelled else { break }
            let time = CMTime(seconds: duration * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            if let (image, _) = try? await generator.image(at: time) {
                images.append(UIImage(cgImage: image))
            }
        }
        return images
    }

    private func formatPrecise(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}

/// プレビュー用の再生を1つの AVPlayer にまとめて管理する。
/// 画面が閉じたあとに読み込みが終わっても再生を始めないよう、close 後の load は破棄する。
@Observable
final class PreviewPlayer {
    let player = AVPlayer()
    private(set) var currentTime = 0.0
    private(set) var isPlaying = false
    private(set) var duration: Double?
    /// iCloud からダウンロード中のときだけ non-nil
    private(set) var downloadProgress: Double?
    @ObservationIgnored private(set) var asset: AVAsset?
    var loopStart = 0.0
    var loopEnd = Double.infinity

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var wasPlayingBeforeSeek = false
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var isLoading = false

    init() {
        player.actionAtItemEnd = .pause
    }

    deinit {
        player.pause()
    }

    @MainActor
    func load(assetID: String) async {
        guard !isLoading, !isClosed, player.currentItem == nil else { return }
        isLoading = true
        defer { isLoading = false }
        // 取得済みならそれを使い、まだなら iCloud からストリーミングで再生を始める
        var item: AVPlayerItem?
        if let cached = PhotoLibrary.cachedAVAsset(for: assetID) {
            item = AVPlayerItem(asset: cached)
        } else {
            item = await PhotoLibrary.streamingPlayerItem(for: assetID)
        }
        if item == nil {
            let asset = try? await PhotoLibrary.avAsset(for: assetID) { value in
                Task { @MainActor [weak self] in
                    guard let self, !self.isClosed, self.player.currentItem == nil else { return }
                    self.downloadProgress = value < 1 ? value : nil
                }
            }
            downloadProgress = nil
            item = asset.map { AVPlayerItem(asset: $0) }
        }
        guard let item, !isClosed else { return }
        let length = try? await item.asset.load(.duration).seconds
        guard !isClosed else { return }

        self.asset = item.asset
        duration = length
        if let length { loopEnd = min(loopEnd, length) }
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30),
                                                      queue: .main) { [weak self] time in
            self?.tick(time.seconds)
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            guard let self, isPlaying else { return }
            seek(to: loopStart)
            player.play()
        }
        play()
    }

    private func tick(_ time: Double) {
        guard !isScrubbing else { return }
        currentTime = time
        // 使う範囲の終わりまで来たら先頭に戻してループ
        if isPlaying, time >= loopEnd - 0.03 { seek(to: loopStart) }
    }

    func play() {
        guard !isClosed, player.currentItem != nil else { return }
        if currentTime < loopStart - 0.05 || currentTime >= loopEnd - 0.05 { seek(to: loopStart) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// トリムのハンドルを動かしている間は止めて、その位置のフレームを表示する
    func scrub(to time: Double) {
        if !isScrubbing {
            isScrubbing = true
            pause()
        }
        seek(to: time)
    }

    /// 再生位置のドラッグ。離したら元の再生状態に戻す
    func seekScrub(to time: Double) {
        if !isScrubbing { wasPlayingBeforeSeek = isPlaying }
        scrub(to: time)
    }

    func endSeekScrub() {
        isScrubbing = false
        if wasPlayingBeforeSeek { play() }
    }

    func endScrub(playFrom time: Double) {
        isScrubbing = false
        seek(to: time)
        play()
    }

    func close() {
        isClosed = true
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }
}

/// 再生コントロールを持たない動画表示
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
