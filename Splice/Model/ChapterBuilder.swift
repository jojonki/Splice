import CoreLocation
import Foundation

/// 撮影時刻と位置からシーンを自動で区切る
enum ChapterBuilder {
    /// この距離以上移動していて、かつ minGapForMove 以上時間があいていれば別シーン
    static let moveDistance: CLLocationDistance = 3_000
    static let minGapForMove: TimeInterval = 15 * 60

    static func build(_ clips: [Clip], gap: TimeInterval, order: ClipOrder = .videosFirst) -> [Chapter] {
        var chapters: [Chapter] = []
        var current: [Clip] = []
        var lastLocation: CLLocation?

        for clip in clips.sorted(by: { $0.date < $1.date }) {
            if let previous = current.last {
                let interval = clip.date.timeIntervalSince(previous.date)
                var moved = false
                if let location = clip.location, let lastLocation {
                    moved = location.distance(from: lastLocation) > moveDistance && interval > minGapForMove
                }
                if interval > gap || moved {
                    chapters.append(Chapter(title: defaultTitle(for: current), clips: current))
                    current = []
                    lastLocation = nil
                }
            }
            current.append(clip)
            if let location = clip.location { lastLocation = location }
        }
        if !current.isEmpty {
            chapters.append(Chapter(title: defaultTitle(for: current), clips: current))
        }
        for i in chapters.indices { chapters[i].arrange(order) }
        return chapters
    }

    static func defaultTitle(for clips: [Clip]) -> String {
        guard let date = clips.map(\.date).min() else { return "" }
        return date.formatted(inApp: .dateTime.month().day().hour().minute())
    }

    /// シーン名を撮影場所の地名に置き換える（取得できなければ日時のまま）
    static func nameByLocation(_ chapters: [Chapter]) async -> [Chapter] {
        var result = chapters
        let geocoder = CLGeocoder()
        for i in result.indices {
            let located = result[i].clips.compactMap(\.location)
            guard !located.isEmpty else { continue }
            let location = located[located.count / 2]
            guard let placemark = try? await geocoder.reverseGeocodeLocation(
                location, preferredLocale: LanguageSettings.shared.locale
            ).first else { continue }
            if let name = placemark.areasOfInterest?.first ?? placemark.subLocality ?? placemark.locality
                ?? placemark.administrativeArea {
                result[i].title = name
            }
        }
        return result
    }

    static func subtitle(for clips: [Clip]) -> String {
        let dates = clips.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return "" }
        let start = first.formatted(inApp: .dateTime.year().month().day())
        if Calendar.current.isDate(first, inSameDayAs: last) { return start }
        return "\(start) – \(last.formatted(inApp: .dateTime.month().day()))"
    }
}
