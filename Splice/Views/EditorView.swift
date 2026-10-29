import PhotosUI
import SwiftUI

struct EditorView: View {
    @Binding var project: Project

    @State private var isExporting = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var detailTarget: Clip?
    @State private var history: [[Chapter]] = []
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var subtitleDraft = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: .sectionHeaders) {
                ForEach(Array(project.chapters.enumerated()), id: \.element.id) { index, chapter in
                    Section {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(chapter.clips) { clip in
                                clipCell(clip)
                            }
                        }
                        .padding(.horizontal, 12)
                    } header: {
                        chapterHeader(chapter, isFirst: index == 0)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(project.title.isEmpty ? L("無題") : project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar } else { bottomBar }
        }
        .task(id: project.allClips.map(\.assetID)) {
            MediaPrefetcher.shared.prefetch(project.allClips, resolution: project.settings.resolution)
        }
        .onChange(of: pickerItems) {
            let ids = pickerItems.compactMap(\.itemIdentifier)
            pickerItems = []
            guard !ids.isEmpty else { return }
            edit { $0.add(PhotoLibrary.clips(forIdentifiers: ids)) }
        }
        .alert("タイトル", isPresented: $isEditingTitle) {
            TextField("タイトル（例：京都旅行）", text: $titleDraft)
            TextField("サブタイトル（日付など）", text: $subtitleDraft)
            Button("キャンセル", role: .cancel) {}
            Button("OK") {
                project.title = titleDraft.trimmingCharacters(in: .whitespaces)
                project.subtitle = subtitleDraft.trimmingCharacters(in: .whitespaces)
            }
        } message: {
            Text("冒頭のタイトル画面に表示されます")
        }
        .fullScreenCover(isPresented: $isExporting) {
            ExportView(project: $project)
        }
        .sheet(item: $detailTarget) { clip in
            ClipBrowserView(project: $project, currentID: clip.id) { edited in
                edit { $0.updateClip(edited.id) { $0 = edited } }
            } onRemove: { id in
                edit { $0.removeClip(id) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                titleDraft = project.title
                subtitleDraft = project.subtitle
                isEditingTitle = true
            } label: {
                HStack(spacing: 4) {
                    Text(project.title.isEmpty ? L("無題") : project.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                // 長いタイトルが左右のボタンにかぶらないよう幅を抑えて末尾を省略する
                .frame(maxWidth: 150)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelecting {
                Button("完了") {
                    isSelecting = false
                    selection = []
                }
                .bold()
            } else {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(history.isEmpty)
                Menu {
                    Section("すべてのシーンを並べ直す") {
                        ForEach(ClipOrder.allCases) { order in
                            Button(order.label) { edit { $0.arrange(order) } }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos]),
                             preferredItemEncoding: .current, photoLibrary: .shared()) {
                    Image(systemName: "plus")
                }
                Button { isSelecting = true } label: { Label("外す", systemImage: "minus.circle") }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(formatDuration(Timeline(project: project).duration)).font(.headline.monospacedDigit())
                if MediaPrefetcher.shared.remaining > 0 {
                    Label(L("iCloudから取得中 残り%lld件", MediaPrefetcher.shared.remaining), systemImage: "icloud.and.arrow.down")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("タップでプレビュー・長押しで並べ替え").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                isExporting = true
            } label: {
                Label("書き出す", systemImage: "film")
            }
            .buttonStyle(.borderedProminent)
            .disabled(project.allClips.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(selection.isEmpty ? L("外す写真・動画をタップ") : L("%lld件を外します", selection.count)).font(.headline)
                Text("写真ライブラリからは削除されません").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                edit { $0.removeClips(selection) }
                selection = []
            } label: {
                Label("ムービーから外す", systemImage: "minus.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selection.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private func chapterHeader(_ chapter: Chapter, isFirst: Bool) -> some View {
        let ids = Set(chapter.clips.map(\.id))
        return ChapterHeader(
            title: Binding(
                get: { chapter.title },
                set: { newValue in project.updateChapter(chapter.id) { $0.title = newValue } }
            ),
            chapter: chapter,
            photoDuration: project.settings.photoDuration,
            isFirst: isFirst,
            selectionState: isSelecting ? (ids.isSubset(of: selection) ? .all : .notAll) : nil,
            onToggleSelectAll: {
                if ids.isSubset(of: selection) { selection.subtract(ids) } else { selection.formUnion(ids) }
            },
            onArrange: { order in edit { $0.updateChapter(chapter.id) { $0.arrange(order) } } },
            onRemovePhotos: { edit { $0.removePhotos(inChapter: chapter.id) } },
            onMerge: { edit { $0.mergeWithPrevious(chapter.id) } },
            onDelete: { edit { $0.removeChapter(chapter.id) } },
            onDropClip: { id in edit { $0.move(id, toChapter: chapter.id) } }
        )
    }

    private func clipCell(_ clip: Clip) -> some View {
        ClipCell(clip: clip, isSelected: isSelecting ? selection.contains(clip.id) : nil) { droppedID in
            edit { $0.move(droppedID, onto: clip.id) }
        }
        .onTapGesture {
            if isSelecting {
                if selection.contains(clip.id) { selection.remove(clip.id) } else { selection.insert(clip.id) }
            } else {
                detailTarget = clip
            }
        }
        .contextMenu {
            Button { detailTarget = clip } label: { Label("プレビュー・トリム", systemImage: "play.rectangle") }
            Divider()
            Button { edit { $0.split(at: clip.id) } } label: {
                Label("ここから新しいシーン", systemImage: "scissors")
            }
            .disabled(!project.canSplit(at: clip.id))
            Button { edit { $0.move(clip.id, by: -1) } } label: { Label("前のシーンへ", systemImage: "arrow.up") }
            Button { edit { $0.move(clip.id, by: 1) } } label: { Label("次のシーンへ", systemImage: "arrow.down") }
            Divider()
            Button(role: .destructive) { edit { $0.removeClip(clip.id) } } label: {
                Label("ムービーから外す", systemImage: "minus.circle")
            }
        }
    }

    /// 構成を変える操作は「元に戻す」できるように履歴を残す
    private func edit(_ change: (inout Project) -> Void) {
        let before = project.chapters
        change(&project)
        guard project.chapters != before else { return }
        history.append(before)
        if history.count > 50 { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        project.chapters = previous
    }
}

private struct ChapterHeader: View {
    enum SelectionState { case all, notAll }

    @Binding var title: String
    let chapter: Chapter
    let photoDuration: Double
    let isFirst: Bool
    /// 選択モード中のみ non-nil
    let selectionState: SelectionState?
    var onToggleSelectAll: () -> Void
    var onArrange: (ClipOrder) -> Void
    var onRemovePhotos: () -> Void
    var onMerge: () -> Void
    var onDelete: () -> Void
    var onDropClip: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("シーン名", text: $title)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let selectionState {
                Button(selectionState == .all ? L("解除") : L("すべて"), action: onToggleSelectAll)
                    .font(.subheadline)
            } else {
                menu
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.bar))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDropClip(id)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var menu: some View {
        Menu {
            Section("このシーンを並べ直す") {
                ForEach(ClipOrder.allCases) { order in
                    Button(order.label) { onArrange(order) }
                }
            }
            Button { onMerge() } label: {
                Label("前のシーンと結合", systemImage: "arrow.up.and.line.horizontal.and.arrow.down")
            }
            .disabled(isFirst)
            Section("写真ライブラリからは削除されません") {
                Button(role: .destructive) { onRemovePhotos() } label: {
                    Label("写真をすべてムービーから外す", systemImage: "photo.badge.minus")
                }
                Button(role: .destructive) { onDelete() } label: {
                    Label("シーンをムービーから外す", systemImage: "minus.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
    }

    private var summary: String {
        let videos = chapter.clips.filter { $0.kind == .video }
        let photos = chapter.clips.filter { $0.kind == .photo }
        let seconds = videos.map(\.trimmedDuration).reduce(0, +) + Double(photos.count) * photoDuration
        var parts: [String] = []
        if let date = chapter.startDate { parts.append(date.formatted(inApp: .dateTime.month().day().hour().minute())) }
        if !videos.isEmpty { parts.append(L("動画 %lld", videos.count)) }
        if !photos.isEmpty { parts.append(L("写真 %lld", photos.count)) }
        parts.append(L("約%@", formatDuration(seconds)))
        return parts.joined(separator: " · ")
    }
}

private struct ClipCell: View {
    let clip: Clip
    /// 選択モード中のみ non-nil
    let isSelected: Bool?
    var onDrop: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay { AssetThumbnail(assetID: clip.assetID, side: 100) }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottomLeading) {
                if clip.kind == .video {
                    Label(formatDuration(clip.trimmedDuration), systemImage: clip.isTrimmed ? "scissors" : "video.fill")
                        .font(.caption2.bold().monospacedDigit())
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 3) {
                    if clip.showsTimestamp { Image(systemName: "clock.fill") }
                    if !clip.caption.isEmpty { Image(systemName: "text.bubble.fill") }
                }
                .font(.caption)
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(4)
            }
            .overlay {
                if isSelected == true {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.3))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let isSelected {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : .black.opacity(0.2))
                        .shadow(radius: 1)
                        .padding(4)
                }
            }
            // ドロップ先の目印：ここに入ることを示す縦線
            .overlay(alignment: .leading) {
                if isTargeted {
                    Capsule().fill(Color.accentColor).frame(width: 4).padding(.vertical, 2).offset(x: -4)
                }
            }
            .contentShape(Rectangle())
            .draggable(clip.id.uuidString) {
                AssetThumbnail(assetID: clip.assetID, side: 80)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                onDrop(id)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

struct AssetThumbnail: View {
    let assetID: String?
    var side: CGFloat
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                }
            }
            .clipped()
            .task(id: assetID) {
                guard let assetID else { return }
                image = await PhotoLibrary.thumbnail(for: assetID, side: side)
            }
    }
}
