# Splice

概要・構成・設計メモ・ビルド/テスト手順は [README.md](README.md) を読むこと。

特に守ること:

- プロジェクト設定は `project.yml` が正。変更したら `xcodegen generate`。`.xcodeproj` を直接編集しない。
- `Clip` / `Project` に保存フィールドを足すときは Optional か既定値付きにする(既存の `projects.json` が読めなくなり、全プロジェクトが消えたように見えるため)。
- 編集ロジックは View ではなく `Project` の mutating メソッドに書き、`TimelineTests` にテストを足す。
- 変更後は README のテストコマンドを実行して通ることを確認する。iCloud 素材や 4K 書き出しはシミュレータでは確かめられない。
- UI の文言とコードコメントは日本語。
