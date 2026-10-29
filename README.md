# Splice

撮りためた写真・動画から、ムービー(mp4)を自動で組み立てて書き出す iPhone アプリ。旅行に限らず、イベントや日常にも使える。
編集は「期間を選ぶ → 自動でシーン分け → 必要なら並べ替え・トリム → 書き出し」まで。凝った編集機能は持たない。

> アプリの表示名は Splice(`project.yml` の `INFOPLIST_KEY_CFBundleDisplayName`)。以前は Simple Tabi Cut という名前だったが、フォルダ名・ターゲット名・スキーム名も `Splice` に揃えた。Bundle ID は `com.jonki.splice`。

- 対象: iOS 17.0 以上、iPhone のみ(縦向き固定)
- 言語: Swift 5 / SwiftUI / Observation。外部ライブラリなし
- 言語: 日本語 / 英語。端末の言語に合わせ(日本語以外は英語)、一覧画面左上の ? メニューから手動で切り替えられる
- Bundle ID: `com.jonki.splice` / Team: `W2Z92AW32J`(`project.yml` に記載)

## 機能

1. **プロジェクト作成** (`NewProjectView`): 最初の画面でタイトルを付け、素材の選び方を「期間を選んで作成」か「写真・動画を選んで作成」から選ぶ。前者は次の画面のカレンダー(`RangeCalendarView`)で開始日 → 終了日をタップして期間を選び、写真・動画の種類やお気に入りで絞り込める。後者は写真ライブラリのピッカーで個別に選ぶ。
2. **シーン自動分割** (`ChapterBuilder`): 撮影時刻の間隔が `chapterGap`(既定 2 時間)を超えたとき、または 3 km 以上移動かつ 15 分以上空いたときに別シーンにする。シーン名は撮影時刻、位置情報があれば逆ジオコーディングした地名。
3. **編集** (`EditorView`): シーンごとのグリッド。ドラッグで並べ替え・別シーンへ移動、シーンの分割と結合、削除、複数選択、素材の追加、アンドゥ(`history`)、並び順(動画 → 写真 / 撮影順)。
4. **素材ごとの設定** (`ClipDetailView`, `TrimTimeline`, `ClipBrowserView`): プレビュー、動画のトリム、キャプション、撮影日時の表示。
5. **書き出し** (`ExportView` → `VideoRenderer`): 解像度(1080p / 4K)、写真の長さ、フェード、音声の有無、タイトル表示を設定して mp4 を生成。写真ライブラリへの保存、共有、YouTube 概要欄用チャプターのコピーができる。設定は `UserDefaults` に残り、次回の既定値になる。
6. **使い方・言語**(`HelpView`, `AppLanguage`): 一覧画面左上の ? メニューから、4 ステップの使い方ページと表示言語(システム / 日本語 / English)を選べる。

## 開発環境

- Xcode 26 系(動作確認: 26.6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### セットアップ

```sh
xcodegen generate          # project.yml から Splice.xcodeproj を再生成
open Splice.xcodeproj
```

**`project.yml` が設定の正**。ターゲット設定・Info.plist のキー(写真ライブラリの利用目的の文言など)を変えるときは `project.yml` を編集して `xcodegen generate` する。`.xcodeproj` を Xcode の GUI で直接いじると、次の generate で消える。`.xcodeproj` 自体はコミット対象(`xcuserdata` のみ除外)。

Info.plist は `GENERATE_INFOPLIST_FILE` で自動生成していて、ファイルとしては存在しない。

### ビルドとテスト

```sh
xcodebuild test -project Splice.xcodeproj -scheme Splice \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath build
```

- `name=` だけだと、同名のシミュレータが複数 OS にあるとき曖昧エラーになる。`OS=` まで指定するか、`xcrun simctl list devices available` で ID を調べて `id=` で指定する。
- `build/` は成果物置き場で、git 管理外。
- 書き出したテスト動画を手元で見たいときは、環境変数 `RENDER_OUT=/path/to/out.mp4` を付けて `RenderTests` を実行する(未指定なら一時ディレクトリ)。

### 実機で確認が必要なもの

シミュレータでは次を確かめられない。変更したら実機で見ること。

- iCloud 上の素材のダウンロード(`MediaPrefetcher`, `PhotoLibrary.avAsset`)
- 実際の写真ライブラリ素材の読み込み(HDR 動画、スローモーション、向き補正)
- 4K 書き出しの速度とメモリ使用量

## 構成

```
project.yml                  XcodeGen 設定(プロジェクト設定の正)
design/icon-source.png       アプリアイコンの元画像(AppIcon.png はここから作った)
Splice/
  SpliceApp.swift     エントリポイント。ProjectStore を environment に注入
  Model/
    Project.swift            Project / Chapter / Clip / ExportSettings と編集操作
    ChapterBuilder.swift     シーン自動分割、シーン名の決定
    ProjectStore.swift       projects.json への永続化、formatDuration
  Render/
    Timeline.swift           Project → 出力動画上の区間列(クロスフェード計算)
    VideoRenderer.swift      Core Image + AVAssetWriter で 1 フレームずつ合成
    VideoFrameReader.swift   動画フレームを先頭から順に取り出す
    OverlayImages.swift      タイトル・シーン名・キャプション・日時の文字画像
  Library/
    PhotoLibrary.swift       PhotoKit のラッパー、PhotoKitMediaProvider
    MediaPrefetcher.swift    iCloud 素材の裏でのダウンロード
  Views/                     SwiftUI の画面(上の「機能」を参照)
SpliceTests/
  TimelineTests.swift        モデル操作・シーン分割・タイムラインの単体テスト
  RenderTests.swift          フィクスチャ素材で実際に mp4 を書き出す結合テスト
  Fixtures/                  テスト用の写真・動画(縦横 2 種ずつ)
```

## 設計メモ

引き継ぐ前に知っておくと迷わない点。

### データモデルと永続化

- `Project` → `Chapter`(動画内の「シーン」) → `Clip`(写真または動画 1 件)。SwiftUI の `Scene` と名前が衝突するため、コード上は `Chapter`。
- 素材そのものは保存しない。`Clip.assetID` は `PHAsset.localIdentifier` で、中身は都度 PhotoKit から読む。ユーザーが写真アプリ側で素材を消すと、書き出し時に `RenderError.cannotLoad` になる。
- 保存先は `Documents/projects.json`。`ProjectStore.projects` の `didSet` で毎回全件を書き出す。
- **保存データの後方互換**: 既存ユーザーの JSON を読み込めなくならないよう、`Clip` にフィールドを足すときは Optional にするか既定値を持たせる。必須キーを足すとデコードに失敗し、`ProjectStore.init` は黙って空配列にする(= 全プロジェクトが見えなくなる)。`Clip.timestampEnabled` が Optional なのはこの理由。
- 編集操作(`split`, `move`, `add` など)は `Project` の mutating メソッドとして実装し、`TimelineTests` で検証している。ロジックは View に書かず、ここに足してテストを書く。
- 並び順の規約: 既定は各シーン内で「動画 → 写真」。別シーンへ移すときは `insertAtBoundary` で、この並びを崩さない位置に入れる。

### 書き出し (最も複雑な部分)

- `Timeline` が `Project` を区間列に変換する。隣り合う区間は重ねてクロスフェードし、重なりは各区間の半分までに制限する。0.3 秒未満の区間は捨てる。YouTube チャプターもここで計算する。
- `VideoRenderer` は 30fps で 1 フレームずつ Core Image で合成し、`AVAssetWriter` で H.264 mp4 に書く。
  - 写真: ゆっくりズーム(Ken Burns、最大 1.06 倍)。最大ズーム時のサイズで一度ラスタライズし、毎フレームは縮小だけにして軽くしている。
  - アスペクト比が合わない素材(縦長など)は、ぼかして暗くした背景を敷く。
  - 区間は、必要になった時点で `prepare`、終わったら `release` する。全素材を同時にメモリに載せない。
  - 音声は動画の音声だけを 2 本のトラックに交互に並べて、映像と同じタイミングでフェードさせる。映像の合成と交互に `pumpAudio` で書き出す。
  - 動画は書き出しの直前に `refresh: true` で取り直す(写真ライブラリが渡すファイルは後から消えることがあるため)。
- 写真・動画の取得は `MediaProvider` プロトコル越し。本番は `PhotoKitMediaProvider`、テストは `RenderTests` 内の `FixtureProvider`(バンドル内のファイル)。レンダラ側のロジックを変えるときはこの差し替え口を使う。
- 書き出し中は `UIApplication.isIdleTimerDisabled` で画面スリープを止めており、アプリを閉じると中断される(バックグラウンド書き出しは未対応)。キャンセルは `Task` のキャンセルで行い、途中のファイルは削除される。

### iCloud 素材

- `MediaPrefetcher` が編集画面を開いている間に、書き出しで使うサイズの写真と動画を裏で取得する。写真と動画で別々に同時実行数を持つ(写真 6、動画 2)ので、大きな動画が写真を止めない。
- 先読みと書き出しの写真リクエストは同じ条件(`PhotoLibrary.renderImageOptions`)にしている。ここを片方だけ変えると、取得済みのデータが使われず、書き出し時に再ダウンロードになる。
- 一覧のサムネイルは端末内のものを優先し、無いときだけネットワークを使う。

### ローカライズ

- 原文は日本語で、**日本語の文言そのものをキー**にする(`Splice/Localizable.xcstrings`、Info.plist の文言は `InfoPlist.xcstrings`)。英語訳はそこに足す。
- SwiftUI のリテラル(`Text("…")`, `Button("…")` など)は自動で翻訳される。`String` で組み立てる文言(三項演算子、補間、エラーメッセージ)は `L("…", 引数)` を使う。引数は `%lld` `%@` `%.1f`、語順が変わるときは `%1$@` 形式。
- 言語は `LanguageSettings`(UserDefaults 保存)で持ち、`ProjectListView` が `\.locale` に流す。日時の整形は `formatted(inApp:)` を使う(システムのロケールを見ないため)。
- 文言を足したら xcstrings に英訳を足すこと(無いと日本語のまま表示される)。

## 既知の制約

- バックグラウンドでの書き出し非対応(上記)。
- 対応言語は日本語と英語のみ。
- BGM、トランジション種類の選択、テキストのフォント・位置の変更はない。
- 縦向き固定。出力は常に 16:9。
- 書き出し結果は H.264 / AAC の mp4 のみ。

## 作業の進め方 (エージェント向け)

- 変更したら上記のテストコマンドを実行する。ロジックの変更には `TimelineTests` にテストを足す。
- 新しい Swift ファイルは該当ディレクトリに置けば、`sources: [Splice]` で自動的にターゲットに入る。`xcodegen generate` で `.xcodeproj` を更新してから確認する。
- コメントは日本語で、既存のコードに合わせて「なぜそうするか」を書く。
