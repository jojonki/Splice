import AVFoundation
import CoreImage
@testable import Splice
import XCTest

/// テストバンドル内のファイルを素材として返す（assetID = ファイル名）
private struct FixtureProvider: MediaProvider {
    func url(_ name: String) -> URL {
        Bundle(for: RenderTests.self).url(forResource: name, withExtension: nil)!
    }

    func image(for clip: Clip, maxDimension: CGFloat) async throws -> CIImage {
        CIImage(contentsOf: url(clip.assetID))!
    }

    func asset(for clip: Clip, refresh: Bool) async throws -> AVAsset {
        AVURLAsset(url: url(clip.assetID))
    }
}

final class RenderTests: XCTestCase {
    func testRenderMixedProject() async throws {
        let now = Date()
        var project = Project(title: "京都旅行", subtitle: "2026年10月20日 – 10月23日")
        project.settings.photoDuration = 2
        project.chapters = [
            Chapter(title: "清水寺", clips: [
                Clip(assetID: "photo_portrait.jpg", kind: .photo, date: now, caption: "夕暮れの三重塔"),
                Clip(assetID: "landscape.mp4", kind: .video, date: now.addingTimeInterval(1), duration: 4,
                     trimStart: 0.5, trimEnd: 3.5),
            ]),
            Chapter(title: "嵐山", clips: [
                Clip(assetID: "portrait.mp4", kind: .video, date: now.addingTimeInterval(9000), duration: 3),
                Clip(assetID: "photo_landscape.jpg", kind: .photo, date: now.addingTimeInterval(9001)),
            ]),
        ]

        project.updateClip(project.chapters[0].clips[0].id) { $0.showsTimestamp = true }

        let outputURL = ProcessInfo.processInfo.environment["RENDER_OUT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appending(path: "render-test.mp4")
        let renderer = VideoRenderer(project: project, provider: FixtureProvider(), outputURL: outputURL)
        var lastProgress = 0.0
        try await renderer.render { lastProgress = $0 }

        XCTAssertEqual(lastProgress, 1)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, renderer.timeline.duration, accuracy: 0.1)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 1)
        let size = try await video[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
        print("Rendered \(duration)s to \(outputURL.path)")
    }
}
