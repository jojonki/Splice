import PhotosUI
import SwiftUI

struct NewProjectView: View {
    var onCreate: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var includeVideos = true
    @State private var includePhotos = true
    @State private var favoritesOnly = false
    @State private var gapHours = 2.0
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var status: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル（例：京都旅行）", text: $title)
                } footer: {
                    Text("冒頭のタイトル画面に表示されます")
                }

                Section("作り方を選ぶ") {
                    NavigationLink {
                        dateRangeForm
                    } label: {
                        modeLabel("期間を選んで作成", systemImage: "calendar",
                                  detail: "カレンダーで日付の範囲を選ぶと、その間に撮った写真・動画をまとめて読み込みます")
                    }
                    PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos]),
                                 preferredItemEncoding: .current, photoLibrary: .shared()) {
                        modeLabel("写真・動画を選んで作成", systemImage: "photo.on.rectangle",
                                  detail: "写真ライブラリから使いたい写真・動画を自分で選びます")
                    }
                    .disabled(isWorking)
                }

                Section {
                    Stepper(value: $gapHours, in: 0.5 ... 12, step: 0.5) {
                        Text(L("%.1f時間あいたら次のシーン", gapHours))
                    }
                } header: {
                    Text("シーンの区切り")
                } footer: {
                    Text("撮影時刻の間隔と移動距離で自動的にシーンを分け、撮影場所の地名をシーン名にします")
                }

                statusSection
            }
            .navigationTitle("新しいムービー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onChange(of: pickerItems) {
                let ids = pickerItems.compactMap(\.itemIdentifier)
                guard !ids.isEmpty else { return }
                Task { await create { PhotoLibrary.clips(forIdentifiers: ids) } }
            }
        }
    }

    /// 作り方の行。PhotosPicker は青字になるので、NavigationLink も同じ色に明示して揃える。
    private func modeLabel(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 2)
    }

    /// 「期間を選んで作成」で開く画面。カレンダーで開始日 → 終了日を選ぶ。
    private var dateRangeForm: some View {
        Form {
            Section {
                RangeCalendarView(start: $startDate, end: $endDate)
                    .padding(.vertical, 4)
            } header: {
                Text("期間")
            } footer: {
                Text("開始日 → 終了日の順にタップ。点は写真・動画がある日です")
            }

            Section {
                Toggle("動画", isOn: $includeVideos)
                Toggle("写真", isOn: $includePhotos)
                Toggle("お気に入りのみ", isOn: $favoritesOnly)
            }

            Section {
                Button("この期間で作成") {
                    Task { await createFromDateRange() }
                }
                .disabled(isWorking || startDate == nil || (!includeVideos && !includePhotos))
            }

            statusSection
        }
        .navigationTitle("期間を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status {
            Section {
                HStack {
                    if isWorking { ProgressView() }
                    Text(status).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func createFromDateRange() async {
        guard let startDate else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let last = calendar.startOfDay(for: endDate ?? startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        await create {
            PhotoLibrary.fetchClips(from: start, to: end, includePhotos: includePhotos,
                                    includeVideos: includeVideos, favoritesOnly: favoritesOnly)
        }
    }

    private func create(fetch: () -> [Clip]) async {
        isWorking = true
        defer { isWorking = false }
        status = L("写真ライブラリを確認中…")
        guard await PhotoLibrary.requestAccess() else {
            status = L("写真へのアクセスが許可されていません。設定アプリから許可してください。")
            return
        }
        let clips = fetch()
        guard !clips.isEmpty else {
            status = L("写真・動画が見つかりませんでした")
            return
        }
        status = L("%lld件をシーンに分けています…", clips.count)
        let gap = gapHours * 3600
        let chapters = await ChapterBuilder.nameByLocation(ChapterBuilder.build(clips, gap: gap))
        let project = Project(title: title, subtitle: ChapterBuilder.subtitle(for: clips),
                              chapterGap: gap, chapters: chapters)
        dismiss()
        onCreate(project)
    }
}
