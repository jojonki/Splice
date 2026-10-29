import CoreGraphics
import CoreLocation
import Foundation

enum MediaKind: String, Codable {
    case photo, video
}

struct Clip: Identifiable, Codable, Hashable {
    var id = UUID()
    /// PHAsset.localIdentifier（テストではファイル名）
    var assetID: String
    var kind: MediaKind
    var date: Date
    /// 動画の長さ（秒）。写真は 0
    var duration: Double = 0
    var latitude: Double?
    var longitude: Double?
    var caption = ""
    /// 古い保存データにはキーが無いので Optional で持つ
    var timestampEnabled: Bool?
    var trimStart: Double = 0
    var trimEnd: Double?

    var trimmedDuration: Double { max(0, (trimEnd ?? duration) - trimStart) }
    var isTrimmed: Bool { trimStart > 0 || trimEnd != nil }

    /// 書き出し時に撮影日時を表示する
    var showsTimestamp: Bool {
        get { timestampEnabled ?? false }
        set { timestampEnabled = newValue }
    }

    var timestampText: String {
        date.formatted(inApp: .dateTime.year().month().day().weekday(.abbreviated).hour().minute())
    }

    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// 動画内の「シーン」。SwiftUI.Scene と名前が衝突するので Chapter と呼ぶ。
struct Chapter: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// この並び順で書き出す
    var clips: [Clip]

    var startDate: Date? { clips.map(\.date).min() }
    var endDate: Date? { clips.map(\.date).max() }

    mutating func arrange(_ order: ClipOrder) {
        let sorted = clips.sorted { $0.date < $1.date }
        switch order {
        case .chronological:
            clips = sorted
        case .videosFirst:
            clips = sorted.filter { $0.kind == .video } + sorted.filter { $0.kind == .photo }
        }
    }

    /// シーンの先頭側／末尾側の境目に入れる。
    /// 「動画 → 写真」の並びになっているシーンでは、その並びを崩さないよう種類ごとのグループの境目に入れる。
    mutating func insertAtBoundary(_ clip: Clip, atHead: Bool) {
        let lastVideo = clips.lastIndex { $0.kind == .video }
        let firstPhoto = clips.firstIndex { $0.kind == .photo }
        let isVideosFirst = lastVideo == nil || firstPhoto == nil || lastVideo! < firstPhoto!
        guard isVideosFirst else {
            clips.insert(clip, at: atHead ? 0 : clips.count)
            return
        }
        let photosStart = lastVideo.map { $0 + 1 } ?? 0
        switch (clip.kind, atHead) {
        case (.video, true): clips.insert(clip, at: 0)
        case (.video, false), (.photo, true): clips.insert(clip, at: photosStart)
        case (.photo, false): clips.append(clip)
        }
    }

    /// 自動で並べたときと同じ位置（動画は動画の末尾、写真は最後）に追加する
    mutating func insert(_ clip: Clip) {
        if clip.kind == .video, let lastVideo = clips.lastIndex(where: { $0.kind == .video }) {
            clips.insert(clip, at: lastVideo + 1)
        } else if clip.kind == .video {
            clips.insert(clip, at: 0)
        } else {
            clips.append(clip)
        }
    }
}

enum ClipOrder: String, Codable, CaseIterable, Identifiable {
    case videosFirst, chronological
    var id: Self { self }
    var label: String {
        switch self {
        case .videosFirst: L("動画 → 写真")
        case .chronological: L("撮影順")
        }
    }
}

enum OutputResolution: String, Codable, CaseIterable, Identifiable {
    case hd1080, uhd4k
    var id: Self { self }
    var label: String {
        switch self {
        case .hd1080: "1080p"
        case .uhd4k: "4K"
        }
    }
    var size: CGSize {
        switch self {
        case .hd1080: CGSize(width: 1920, height: 1080)
        case .uhd4k: CGSize(width: 3840, height: 2160)
        }
    }
    var bitRate: Int {
        switch self {
        case .hd1080: 16_000_000
        case .uhd4k: 45_000_000
        }
    }
}

struct ExportSettings: Codable, Hashable {
    var photoDuration: Double = 3
    var fadeDuration: Double = 0.6
    var keepAudio = true
    var showOpeningTitle = true
    var showChapterTitles = true
    var resolution: OutputResolution = .hd1080

    private static let defaultsKey = "lastExportSettings"

    /// 前回書き出したときの設定
    static var lastUsed: ExportSettings {
        get {
            UserDefaults.standard.data(forKey: defaultsKey)
                .flatMap { try? JSONDecoder().decode(ExportSettings.self, from: $0) } ?? ExportSettings()
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: defaultsKey)
        }
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var subtitle: String = ""
    var createdAt = Date()
    var chapterGap: TimeInterval = 2 * 3600
    var chapters: [Chapter] = []
    var settings = ExportSettings.lastUsed

    var allClips: [Clip] { chapters.flatMap(\.clips) }
}

// MARK: - 編集操作

extension Project {
    func clip(id: UUID) -> Clip? {
        allClips.first { $0.id == id }
    }

    private func locate(_ clipID: UUID) -> (chapter: Int, clip: Int)? {
        for (ci, chapter) in chapters.enumerated() {
            if let i = chapter.clips.firstIndex(where: { $0.id == clipID }) { return (ci, i) }
        }
        return nil
    }

    mutating func updateClip(_ id: UUID, _ body: (inout Clip) -> Void) {
        guard let (ci, i) = locate(id) else { return }
        body(&chapters[ci].clips[i])
    }

    mutating func updateChapter(_ id: UUID, _ body: (inout Chapter) -> Void) {
        guard let i = chapters.firstIndex(where: { $0.id == id }) else { return }
        body(&chapters[i])
    }

    mutating func removeClip(_ id: UUID) {
        guard let (ci, i) = locate(id) else { return }
        chapters[ci].clips.remove(at: i)
        chapters.removeAll { $0.clips.isEmpty }
    }

    mutating func removeClips(_ ids: Set<UUID>) {
        for i in chapters.indices { chapters[i].clips.removeAll { ids.contains($0.id) } }
        chapters.removeAll { $0.clips.isEmpty }
    }

    mutating func removeChapter(_ id: UUID) {
        chapters.removeAll { $0.id == id }
    }

    mutating func removePhotos(inChapter id: UUID) {
        updateChapter(id) { $0.clips.removeAll { $0.kind == .photo } }
        chapters.removeAll { $0.clips.isEmpty }
    }

    mutating func arrange(_ order: ClipOrder) {
        for i in chapters.indices { chapters[i].arrange(order) }
    }

    mutating func mergeWithPrevious(_ id: UUID) {
        guard let i = chapters.firstIndex(where: { $0.id == id }), i > 0 else { return }
        chapters[i - 1].clips += chapters[i].clips
        chapters.remove(at: i)
    }

    func canSplit(at clipID: UUID) -> Bool {
        guard let (_, i) = locate(clipID) else { return false }
        return i > 0
    }

    /// 指定クリップ以降を新しいシーンに分ける
    mutating func split(at clipID: UUID) {
        guard let (ci, i) = locate(clipID), i > 0 else { return }
        let later = Array(chapters[ci].clips[i...])
        chapters[ci].clips.removeSubrange(i...)
        chapters.insert(Chapter(title: ChapterBuilder.defaultTitle(for: later), clips: later), at: ci + 1)
    }

    /// 隣のシーンへ移動（offset: -1 で前、+1 で次）
    mutating func move(_ clipID: UUID, by offset: Int) {
        guard let (ci, _) = locate(clipID), chapters.indices.contains(ci + offset) else { return }
        move(clipID, toChapter: chapters[ci + offset].id)
    }

    /// ドラッグしたクリップを target の位置へ移動する。
    /// 同じシーン内で後ろへ動かすときは target の後ろ、それ以外は target の前に入る。
    mutating func move(_ clipID: UUID, onto targetID: UUID) {
        guard clipID != targetID, let (sc, si) = locate(clipID), let (tc, ti) = locate(targetID) else { return }
        let clip = chapters[sc].clips.remove(at: si)
        // 同じシーン内で後ろへ動かす場合、remove で target が1つ前にずれるので ti に入れると target の後ろになる
        chapters[tc].clips.insert(clip, at: min(ti, chapters[tc].clips.count))
        chapters.removeAll { $0.clips.isEmpty }
    }

    /// 別のシーンへ移動する。後ろのシーンへは先頭側、前のシーンへは末尾側の境目に入れるので、
    /// 隣のシーンとの間で動かす限り撮影時刻の順が保たれる。同じシーンなら末尾へ。
    mutating func move(_ clipID: UUID, toChapter chapterID: UUID) {
        guard let (sc, si) = locate(clipID), let tc = chapters.firstIndex(where: { $0.id == chapterID }) else { return }
        let clip = chapters[sc].clips.remove(at: si)
        if sc == tc {
            chapters[tc].clips.append(clip)
        } else {
            chapters[tc].insertAtBoundary(clip, atHead: sc < tc)
        }
        chapters.removeAll { $0.clips.isEmpty }
    }

    /// 新しい素材を撮影時刻の近いシーンへ振り分ける
    mutating func add(_ newClips: [Clip]) {
        let existing = Set(allClips.map(\.assetID))
        let fresh = newClips.filter { !existing.contains($0.assetID) }.sorted { $0.date < $1.date }
        for clip in fresh {
            let nearest = chapters.indices.min {
                distance(from: clip.date, to: chapters[$0]) < distance(from: clip.date, to: chapters[$1])
            }
            if let nearest, distance(from: clip.date, to: chapters[nearest]) <= chapterGap {
                chapters[nearest].insert(clip)
            } else {
                chapters.append(Chapter(title: ChapterBuilder.defaultTitle(for: [clip]), clips: [clip]))
                chapters.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            }
        }
    }

    private func distance(from date: Date, to chapter: Chapter) -> TimeInterval {
        guard let start = chapter.startDate, let end = chapter.endDate else { return .infinity }
        if date < start { return start.timeIntervalSince(date) }
        if date > end { return date.timeIntervalSince(end) }
        return 0
    }
}
