import SwiftUI

/// 写真アプリ風のトリムバー。コマを並べたフィルムストリップの両端を黄色いハンドルで挟む。
struct TrimTimeline: View {
    let duration: Double
    let frames: [UIImage]
    @Binding var start: Double
    @Binding var end: Double
    /// 再生位置（白い縦線）
    let playhead: Double
    var minimumLength = 1.0
    /// ハンドルをドラッグ中に、その位置を表示するため呼ばれる
    var onScrub: (Double) -> Void
    /// ハンドルを離したとき。true なら開始側
    var onScrubEnd: (_ isStart: Bool) -> Void
    /// 範囲内をドラッグして再生位置を動かしている間
    var onSeek: (Double) -> Void
    var onSeekEnd: () -> Void

    @State private var startOrigin: Double?
    @State private var endOrigin: Double?

    private let handleWidth: CGFloat = 18
    private let height: CGFloat = 56

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - handleWidth * 2)
            let x = { (t: Double) in handleWidth + CGFloat(t / max(duration, 0.01)) * trackWidth }
            let startX = x(start), endX = x(end)

            ZStack(alignment: .topLeading) {
                filmstrip(width: trackWidth)
                    .offset(x: handleWidth)

                // 使わない部分は暗くする
                Color.black.opacity(0.6)
                    .frame(width: max(0, startX - handleWidth), height: height)
                    .offset(x: handleWidth)
                Color.black.opacity(0.6)
                    .frame(width: max(0, handleWidth + trackWidth - endX), height: height)
                    .offset(x: endX)

                // 選択範囲の黄色い枠
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: endX - startX + handleWidth * 2, height: height)
                    .offset(x: startX - handleWidth)
                    .allowsHitTesting(false)

                // 範囲内のどこをドラッグしても再生位置を動かせる
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: max(0, endX - startX), height: height)
                    .offset(x: startX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimTrack"))
                        .onChanged { value in
                            let time = Double((value.location.x - handleWidth) / trackWidth) * duration
                            onSeek(min(max(time, start), end))
                        }
                        .onEnded { _ in onSeekEnd() })

                handle(systemImage: "chevron.compact.left")
                    .offset(x: startX - handleWidth)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let origin = startOrigin ?? start
                            startOrigin = origin
                            let delta = Double(value.translation.width / trackWidth) * duration
                            start = min(max(0, origin + delta), end - minimumLength)
                            onScrub(start)
                        }
                        .onEnded { _ in
                            startOrigin = nil
                            onScrubEnd(true)
                        })

                handle(systemImage: "chevron.compact.right")
                    .offset(x: endX)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let origin = endOrigin ?? end
                            endOrigin = origin
                            let delta = Double(value.translation.width / trackWidth) * duration
                            end = max(min(duration, origin + delta), start + minimumLength)
                            onScrub(end)
                        }
                        .onEnded { _ in
                            endOrigin = nil
                            onScrubEnd(false)
                        })

                // 再生位置。上端の丸がつまみ
                VStack(spacing: 0) {
                    Circle().fill(.white).frame(width: 12, height: 12)
                    Capsule().fill(.white).frame(width: 3, height: height + 2)
                }
                .shadow(radius: 1)
                .offset(x: x(min(max(playhead, start), end)) - 6, y: -10)
                .allowsHitTesting(false)
            }
            .coordinateSpace(name: "trimTrack")
        }
        .frame(height: height)
    }

    private func filmstrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if frames.isEmpty {
                Color.secondary.opacity(0.3)
            } else {
                ForEach(frames.indices, id: \.self) { i in
                    Image(uiImage: frames[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(frames.count), height: height)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func handle(systemImage: String) -> some View {
        Color.yellow
            .frame(width: handleWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                Image(systemName: systemImage)
                    .font(.title2.bold())
                    .foregroundStyle(.black.opacity(0.7))
            }
            .contentShape(Rectangle().inset(by: -10))
    }
}
