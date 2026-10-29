@testable import Splice
import XCTest

final class TimelineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func photo(_ minutes: Double) -> Clip {
        Clip(assetID: UUID().uuidString, kind: .photo, date: base.addingTimeInterval(minutes * 60))
    }

    private func video(_ minutes: Double, duration: Double) -> Clip {
        Clip(assetID: UUID().uuidString, kind: .video, date: base.addingTimeInterval(minutes * 60), duration: duration)
    }

    func testChaptersSplitByTimeGap() {
        let clips = [photo(0), video(10, duration: 5), photo(200), photo(210)]
        let chapters = ChapterBuilder.build(clips, gap: 2 * 3600)
        XCTAssertEqual(chapters.map(\.clips.count), [2, 2])
    }

    func testVideosComeFirstInChapter() {
        let chapters = ChapterBuilder.build([photo(0), video(1, duration: 3), photo(2), video(3, duration: 3)], gap: 3600)
        XCTAssertEqual(chapters[0].clips.map(\.kind), [.video, .video, .photo, .photo])
    }

    func testCrossfadeOverlaps() {
        var project = Project(title: "Trip")
        project.settings.photoDuration = 3
        project.settings.fadeDuration = 0.5
        project.chapters = [
            Chapter(title: "A", clips: [video(2, duration: 4), photo(0)]),
            Chapter(title: "B", clips: [photo(300)]),
        ]
        let timeline = Timeline(project: project)
        // タイトル3 + 動画4 + 写真3 + 写真3 − フェード0.5×3
        XCTAssertEqual(timeline.items.count, 4)
        XCTAssertEqual(timeline.duration, 13 - 1.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.items[1].start, 2.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.items[1].chapterTitle, "A")
        XCTAssertNil(timeline.items[2].chapterTitle)
        XCTAssertEqual(timeline.items[3].chapterTitle, "B")
        XCTAssertEqual(timeline.youtubeChapterText, "0:00 A\n0:08 B")
    }

    func testSplitAndMerge() {
        var project = Project(title: "Trip")
        project.chapters = ChapterBuilder.build([photo(0), photo(5), photo(10)], gap: 3600)
        let middle = project.chapters[0].clips[1].id
        project.split(at: middle)
        XCTAssertEqual(project.chapters.map(\.clips.count), [1, 2])
        project.mergeWithPrevious(project.chapters[1].id)
        XCTAssertEqual(project.chapters.map(\.clips.count), [3])
    }

    func testDragMove() {
        var project = Project(title: "Trip")
        let a = photo(0), b = photo(1), c = photo(2), d = photo(300)
        project.chapters = [Chapter(title: "A", clips: [a, b, c]), Chapter(title: "B", clips: [d])]
        // 後ろへ：target の後ろに入る
        project.move(a.id, onto: c.id)
        XCTAssertEqual(project.chapters[0].clips.map(\.id), [b.id, c.id, a.id])
        // 前へ：target の前に入る
        project.move(a.id, onto: b.id)
        XCTAssertEqual(project.chapters[0].clips.map(\.id), [a.id, b.id, c.id])
        // 別シーンへ。空になったシーンは消える
        project.move(d.id, onto: b.id)
        XCTAssertEqual(project.chapters.count, 1)
        XCTAssertEqual(project.chapters[0].clips.map(\.id), [a.id, d.id, b.id, c.id])
        project.removeClip(d.id)
        XCTAssertEqual(project.allClips.count, 3)
    }

    func testMoveToAdjacentChapterKeepsBoundary() {
        var project = Project(title: "Trip")
        let v1 = video(0, duration: 3), p1 = photo(1)
        let v2 = video(100, duration: 3), p2 = photo(101)
        let v3 = video(200, duration: 3), p3 = photo(201)
        project.chapters = [Chapter(title: "A", clips: [v1, p1]), Chapter(title: "B", clips: [v2, p2]),
                            Chapter(title: "C", clips: [v3, p3])]
        // 前のシーンの末尾 → 動画は動画グループの末尾、写真は末尾
        project.move(v2.id, by: -1)
        project.move(p2.id, by: -1)
        XCTAssertEqual(project.chapters[0].clips.map(\.id), [v1.id, v2.id, p1.id, p2.id])
        // B が空になって消えたので C が2番目。次のシーンの先頭 → 写真は写真グループの先頭
        project.move(p1.id, by: 1)
        XCTAssertEqual(project.chapters[1].clips.map(\.id), [v3.id, p1.id, p3.id])
        // 混在して並べ替え済みのシーンは単純に先頭へ
        project.chapters[1].clips = [p1, v3, p3]
        project.move(v2.id, by: 1)
        XCTAssertEqual(project.chapters[1].clips.map(\.id), [v2.id, p1.id, v3.id, p3.id])
    }

    func testAddPutsClipIntoNearestChapter() {
        var project = Project(title: "Trip", chapterGap: 3600)
        project.chapters = ChapterBuilder.build([photo(0), photo(10), photo(500)], gap: 3600)
        project.add([photo(20), photo(1000)])
        XCTAssertEqual(project.chapters.map(\.clips.count), [3, 1, 1])
    }
}
