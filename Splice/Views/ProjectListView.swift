import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @State private var path: [UUID] = []
    @State private var isCreating = false
    @State private var isShowingHelp = false
    @Bindable private var languageSettings = LanguageSettings.shared

    var body: some View {
        // locale は文言の言語を切り替える。ここで読むので、言語を変えると全画面が再描画される
        NavigationStack(path: $path) {
            List {
                ForEach(store.projects) { project in
                    NavigationLink(value: project.id) {
                        HStack(spacing: 12) {
                            AssetThumbnail(assetID: project.allClips.first?.assetID, side: 56)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title.isEmpty ? L("無題") : project.title).font(.headline)
                                Text(L("%@  ·  %lldシーン  ·  %@", project.subtitle, project.chapters.count, formatDuration(Timeline(project: project).duration)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { store.projects.remove(atOffsets: $0) }
            }
            .navigationTitle("ムービー")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { isShowingHelp = true } label: { Label("使い方", systemImage: "questionmark.circle") }
                        Picker("言語", selection: $languageSettings.language) {
                            Text("システムに合わせる").tag(AppLanguage.system)
                            Text(verbatim: "日本語").tag(AppLanguage.ja)
                            Text(verbatim: "English").tag(AppLanguage.en)
                        }
                    } label: { Image(systemName: "questionmark.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCreating = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView("まだムービーがありません", systemImage: "film.stack",
                                           description: Text("右上の ＋ から作成します。撮影した期間を選ぶか、使う写真・動画を自分で選べます"))
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let binding = store.binding(for: id) {
                    EditorView(project: binding)
                }
            }
            .sheet(isPresented: $isShowingHelp) { HelpView() }
            .sheet(isPresented: $isCreating) {
                NewProjectView { project in
                    store.projects.insert(project, at: 0)
                    path.append(project.id)
                }
            }
        }
        .environment(\.locale, languageSettings.locale)
    }
}
