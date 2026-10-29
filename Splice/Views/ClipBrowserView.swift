import SwiftUI

/// プレビューを開いたまま、ムービー全体の並び順で前後の素材へ移動する
struct ClipBrowserView: View {
    @Binding var project: Project
    @State var currentID: UUID
    var onSave: (Clip) -> Void
    var onRemove: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    private var clips: [Clip] { project.allClips }
    private var index: Int? { clips.firstIndex { $0.id == currentID } }

    var body: some View {
        NavigationStack {
            Group {
                if let index {
                    let clip = clips[index]
                    ClipDetailView(clip: clip, onSave: onSave) {
                        remove(at: index)
                    } onSwipe: { offset in
                        go(offset)
                    }
                    .id(clip.id)
                    .transition(.opacity)
                }
            }
            .task(id: currentID) {
                // 開いている素材と次の2件を先読みの先頭へ
                guard let index else { return }
                MediaPrefetcher.shared.prioritize(Array(clips[index ..< min(index + 3, clips.count)]))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(chapterTitle.isEmpty ? L("無題のシーン") : chapterTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(positionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { go(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled((index ?? 0) <= 0)
                    Spacer()
                    Text(title).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button { go(1) } label: { Image(systemName: "chevron.right") }
                        .disabled((index ?? clips.count) >= clips.count - 1)
                }
            }
        }
    }

    private var title: String {
        guard let index else { return "" }
        return "\(index + 1) / \(clips.count)"
    }

    private var chapterIndex: Int? {
        project.chapters.firstIndex { $0.clips.contains { $0.id == currentID } }
    }

    private var chapterTitle: String {
        chapterIndex.map { project.chapters[$0].title } ?? ""
    }

    /// 例：「シーン 2/5 · 3枚目 / 12」
    private var positionText: String {
        guard let ci = chapterIndex,
              let i = project.chapters[ci].clips.firstIndex(where: { $0.id == currentID }) else { return "" }
        return L("シーン %lld/%lld · %lld件目 / %lld", ci + 1, project.chapters.count, i + 1, project.chapters[ci].clips.count)
    }

    private func go(_ offset: Int) {
        guard let index, clips.indices.contains(index + offset) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { currentID = clips[index + offset].id }
    }

    /// 外したら次の素材（末尾なら前の素材）を表示する。何も残らなければ閉じる。
    private func remove(at index: Int) {
        let neighbor = clips.indices.contains(index + 1) ? clips[index + 1].id
            : clips.indices.contains(index - 1) ? clips[index - 1].id : nil
        onRemove(clips[index].id)
        if let neighbor {
            currentID = neighbor
        } else {
            dismiss()
        }
    }
}
