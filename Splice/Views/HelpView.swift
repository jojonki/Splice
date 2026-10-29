import SwiftUI

/// 作り方を4ステップで伝えるだけのシンプルな使い方ページ
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                step(1, "calendar", "素材を選ぶ",
                     "一覧の右上の ＋ から新しいムービーを作ります。撮影した期間を選ぶか、使う写真・動画を自分で選びます。")
                step(2, "square.grid.2x2", "シーンを確認する",
                     "撮影時刻の間隔や移動距離で、自動的にシーンに分かれます。シーン名は撮影場所の地名になります。")
                step(3, "hand.draw", "並べ替える・整える",
                     "長押ししてドラッグで並べ替え。タップするとプレビューと動画のトリム、キャプションの入力ができます。")
                step(4, "film", "書き出す",
                     "画面下の「書き出す」で解像度や写真の長さを決めて mp4 を作ります。写真ライブラリへの保存や共有ができます。")
                Section {
                    Text("元の写真・動画は削除されません。ムービーから外しても、写真ライブラリには残ります。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完了") { dismiss() }
            }
        }
    }

    private func step(_ number: Int, _ systemImage: String, _ title: LocalizedStringKey,
                      _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("ステップ %lld", number)).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
