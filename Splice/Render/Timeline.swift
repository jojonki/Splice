import Foundation

/// 出力動画上の1区間（タイトルカード／写真／動画）
struct TimelineItem {
    enum Content {
        case titleCard(title: String, subtitle: String)
        case clip(Clip)
    }

    var content: Content
    var duration: Double
    var start: Double = 0
    /// 前の区間（先頭なら黒）からのクロスフェード時間
    var fadeIn: Double = 0
    /// 次の区間（末尾なら黒）へのクロスフェード時間
    var fadeOut: Double = 0
    /// シーンの先頭区間にだけ入るシーン名
    var chapterTitle: String?

    var end: Double { start + duration }
}

struct Timeline {
    static let titleCardDuration = 3.0

    private(set) var items: [TimelineItem] = []
    private(set) var duration: Double = 0

    init(project: Project) {
        let settings = project.settings
        if settings.showOpeningTitle, !project.title.isEmpty {
            items.append(TimelineItem(content: .titleCard(title: project.title, subtitle: project.subtitle),
                                      duration: Self.titleCardDuration))
        }
        for chapter in project.chapters {
            var isFirst = true
            for clip in chapter.clips {
                let duration = clip.kind == .photo ? settings.photoDuration : clip.trimmedDuration
                guard duration >= 0.3 else { continue }
                let title = isFirst && settings.showChapterTitles && !chapter.title.isEmpty ? chapter.title : nil
                items.append(TimelineItem(content: .clip(clip), duration: duration, chapterTitle: title))
                isFirst = false
            }
        }

        // 隣り合う区間を重ねてクロスフェードさせる。重なりは各区間の半分まで。
        let fade = settings.fadeDuration
        var time = 0.0
        for i in items.indices {
            items[i].start = time
            if i == 0 { items[i].fadeIn = min(fade, items[i].duration / 2) }
            if i + 1 < items.count {
                let overlap = min(fade, items[i].duration / 2, items[i + 1].duration / 2)
                items[i].fadeOut = overlap
                items[i + 1].fadeIn = overlap
                time += items[i].duration - overlap
            } else {
                items[i].fadeOut = min(fade, items[i].duration / 2)
            }
        }
        duration = items.last?.end ?? 0
    }

    /// YouTube 概要欄用のチャプター（先頭は必ず 0:00）
    var chapterMarks: [(time: Double, title: String)] {
        var marks = items.compactMap { item in item.chapterTitle.map { (time: item.start, title: $0) } }
        if !marks.isEmpty { marks[0].time = 0 }
        return marks
    }

    var youtubeChapterText: String {
        chapterMarks.map { "\(formatDuration($0.time.rounded(.down))) \($0.title)" }.joined(separator: "\n")
    }
}
