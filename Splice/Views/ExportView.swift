import AVKit
import SwiftUI

/// 設定確認 → 書き出し → 保存・共有 を1画面で進める
struct ExportView: View {
    @Binding var project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var isRendering = false
    @State private var progress = 0.0
    @State private var outputURL: URL?
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var saveState: String?
    @State private var task: Task<Void, Never>?
    @State private var copiedChapters = false

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView("書き出しに失敗しました", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if let outputURL {
                    finished(outputURL)
                } else if isRendering {
                    rendering
                } else {
                    settingsForm
                }
            }
            .navigationTitle(isRendering || outputURL != nil ? L("書き出し") : L("書き出し設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outputURL == nil && errorMessage == nil ? L("キャンセル") : L("閉じる")) {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            task?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var settingsForm: some View {
        Form {
            Section("タイトル画面") {
                Toggle("冒頭にタイトルを表示", isOn: $project.settings.showOpeningTitle)
                if project.settings.showOpeningTitle {
                    TextField("タイトル", text: $project.title)
                    TextField("サブタイトル（日付など）", text: $project.subtitle)
                }
            }
            Section("文字・音") {
                Toggle("シーン名を表示", isOn: $project.settings.showChapterTitles)
                Toggle("動画の音声を使う", isOn: $project.settings.keepAudio)
            }
            Section("長さ") {
                Stepper(value: $project.settings.photoDuration, in: 1 ... 8, step: 0.5) {
                    Text(L("写真1枚 %.1f秒", project.settings.photoDuration))
                }
                Stepper(value: $project.settings.fadeDuration, in: 0 ... 2, step: 0.1) {
                    Text(L("フェード %.1f秒", project.settings.fadeDuration))
                }
            }
            Section {
                Picker("解像度", selection: $project.settings.resolution) {
                    ForEach(OutputResolution.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("解像度")
            } footer: {
                Text("設定は次回の書き出しにも引き継がれます")
            }
            Section {
                Button {
                    start()
                } label: {
                    Text(L("書き出し開始（%@）", formatDuration(Timeline(project: project).duration)))
                        .frame(maxWidth: .infinity)
                        .bold()
                }
            }
        }
    }

    private var rendering: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: progress) {
                Text(L("書き出し中… %lld%%", Int(progress * 100)))
            }
            Text("完了するまでアプリを開いたままにしてください")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func finished(_ url: URL) -> some View {
        let timeline = Timeline(project: project)
        return ScrollView {
            VStack(spacing: 16) {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                Button {
                    Task { await save(url) }
                } label: {
                    Label(saveState ?? L("写真に保存"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(saveState != nil)

                ShareLink(item: url) {
                    Label("共有", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if timeline.chapterMarks.count >= 3 {
                    Button {
                        UIPasteboard.general.string = timeline.youtubeChapterText
                        copiedChapters = true
                    } label: {
                        Label(copiedChapters ? L("コピーしました") : L("チャプター情報をコピー（YouTube用）"),
                              systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Text("写真に保存したあと、YouTubeアプリの「＋」からアップロードできます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func start() {
        guard task == nil else { return }
        ExportSettings.lastUsed = project.settings
        isRendering = true
        UIApplication.shared.isIdleTimerDisabled = true
        // タイトルに / などが入っているとパスとして壊れるので、ファイル名に使えない文字は置き換える
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let name = project.title.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name.isEmpty ? "movie" : name).mp4")
        let renderer = VideoRenderer(project: project, provider: PhotoKitMediaProvider(), outputURL: url)
        task = Task {
            do {
                try await renderer.render { value in
                    Task { @MainActor in progress = value }
                }
                outputURL = url
                player = AVPlayer(url: url)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
            isRendering = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func save(_ url: URL) async {
        saveState = L("保存中…")
        do {
            try await PhotoLibrary.saveVideo(at: url)
            saveState = L("保存しました")
        } catch {
            saveState = nil
            errorMessage = error.localizedDescription
        }
    }
}
