# App Store 掲載情報

App Store Connect の各項目を、日英とも貼り付けられる形でまとめる。コードブロックの中身がそのまま入力値。
文字数は App Store Connect の数え方(全角も 1 文字)。編集したら末尾の計測コマンドで測り直し、見出しと表を直す。

| 項目 | 上限 | en-US | ja |
|---|---:|---:|---:|
| name | 30 | 25 | 20 |
| subtitle | 30 | 25 | 15 |
| keywords | 100 | 99 | 63 |
| promotional_text | 170 | 132 | 58 |
| description | 4000 | 1885 | 833 |

---

## 共通

- **Bundle ID**: `com.jonki.splice` / **SKU**: `splice`(任意)
- **主カテゴリ**: 写真/ビデオ(Photo & Video) / **副カテゴリ**: なし(旅行などに限定しない。付けるなら「エンターテインメント」)
- **対応端末**: iPhone のみ(iOS 17.0 以上、縦向き固定)
- **価格**: 無料(0円)。アプリ内課金・広告なし。App 内に StoreKit のコードはないので、「有料App契約」や銀行口座・税務情報の登録は不要
- **年齢制限**: 4+(ユーザー生成コンテンツ・ネット接続・課金なし)
- **App のプライバシー**: 「データを収集しません」。通信処理も解析 SDK もない(`grep -rn "URLSession\|StoreKit" Splice` が空であること。住所の地名は端末の `CLGeocoder` による逆ジオコーディングのみで、Apple のサービスに位置情報を送るが、開発者は何も受け取らない)
- **輸出コンプライアンス**: 暗号化は標準の OS 機能のみ(`project.yml` の `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` = NO で設定済み)
- **サポート URL / マーケティング URL**: 必須。`https://jojonki.github.io/simple-tabi-cut/`(`docs/index.html`。GitHub Pages の Settings で `main` の `/docs` を公開する)
- **プライバシーポリシー URL**: 必須。`https://jojonki.github.io/simple-tabi-cut/privacy.html`(`docs/privacy.html`。日英併記)
- **著作権**: `2026 Junki Ohmura`
- **スクリーンショット**: `AppStore/screenshots/final/` 下。「Dynamic Island (medium)」(必須)には `1206x2622/<ja|en-US>/`、「Dynamic Island (large)」には `1320x2868/<ja|en-US>/` を、番号順に 5 枚アップロードする。他のスロット(Face ID、Home Button など)は大きい方から自動で縮小される。

## en-US

### Name — 25 / 30

```
Splice: Photo Video Maker
```

### Subtitle — 25 / 30

```
Turn clips into one movie
```

### Keywords — 99 / 100

```
slideshow,travel,vacation,memories,montage,video,movie,cut,highlights,editor,clips,album,diary,vlog
```

### Promotional text — 132 / 170

```
Pick the dates and your photos and videos are gathered into scenes. Rearrange them and save your movie. No ads, no in-app purchases.
```

### Description — 1885 / 4000

```
Splice puts the photos and videos you already shot into one movie. Pick the dates, and your clips are gathered for you; then rearrange, shorten and save. There is no complicated timeline to learn. Use it for trips, events, birthdays or everyday life.

No ads. No in-app purchases. No account.

PICK THE DATES
Tap a start day and an end day on the calendar, and every photo and video from those days is pulled in. Filter by photos, videos or favorites. Or choose the clips yourself from your library.

SCENES
Your footage is split into scenes by the gaps between shots and the distance you travelled. Each scene is named after the place where it was taken, so a few days of clips start out organized by time and location.

TIDY IT UP
- Drag to reorder clips, or move them between scenes
- Split and merge scenes, remove clips you do not want
- Tap any clip to preview it, cut a video down to the best part and add a caption
- Sort each scene videos first, or in shooting order
- Undo whenever you change your mind

EXPORT
Choose the picture quality (standard or extra high), how long each photo stays on screen, how smoothly one clip blends into the next, whether to keep the sound from your videos and whether to show a title screen and scene names. Splice makes a movie you can save to Photos or share. It can also copy a table of contents to paste into a YouTube description. Your settings are remembered for next time.

KEEP YOUR ORIGINALS SAFE
Splice never changes or deletes your photos and videos. Removing a clip from a movie only removes it from the movie.

PRIVATE BY DESIGN
No account, no ads, no in-app purchases, no tracking. Everything is processed on your iPhone, and nothing is uploaded anywhere. Scene names are looked up from your photos' locations using Apple's built-in service, which needs a connection.

Available in English and Japanese. Requires iOS 17 or later.
```

### What's New (1.0)

```
First release.
```

### Review notes

```
Splice needs access to the user's Photos library to read the photos and videos they choose and to save the exported movie. No account is required and the app sends no data to the developer. To try it: tap + on the first screen, tap "Create from a date range", choose a range that contains photos or videos and tap "Create for this range". Scene names come from on-device reverse geocoding of photo locations, which needs a network connection.
```

---

## ja

### 名前 — 20 / 30

```
Splice - 写真・動画ムービー作成
```

### サブタイトル — 15 / 30

```
写真と動画を、1本のムービーに
```

### キーワード — 63 / 100

```
スライドショー,旅行,思い出,動画編集,写真,ムービー,高画質,カット,ダイジェスト,アルバム,Vlog,日記,イベント,動画
```

### プロモーションテキスト — 58 / 170

```
期間を選ぶと、撮りためた写真・動画がシーンごとに集まります。並べ替えて、ムービーを保存。広告なし、アプリ内課金なし。
```

### 概要 — 833 / 4000

```
Splice は、撮りためた写真・動画を1本のムービーにまとめるアプリです。期間を選ぶと素材が集まり、あとは並べ替えて、短く切って、保存するだけ。むずかしいタイムラインはありません。旅行、イベント、誕生日、毎日の記録など、用途は選びません。

広告なし。アプリ内課金なし。アカウント登録なし。

期間を選ぶだけ
カレンダーで開始日と終了日をタップすると、その間に撮った写真・動画をまとめて読み込みます。写真・動画・お気に入りで絞り込めるほか、写真ライブラリから使いたい素材を自分で選ぶこともできます。

シーン分け
撮影の間隔と移動距離をもとに、素材をシーンに分けます。シーン名は撮影した場所の地名。数日分の素材も、時間・場所ごとに整理された状態で始められます。

整える
・ドラッグで並べ替え、別のシーンへ移動
・シーンの分割・結合、不要な素材の取り外し
・素材をタップしてプレビュー。動画は使いたい部分だけに切り取り、キャプションも入力
・シーンごとに「動画 → 写真」または撮影順に並べ替え
・アンドゥでいつでも元に戻せます

書き出し
画質は「標準」と「高画質」から。写真の表示時間、つなぎ目のなめらかさ、動画の音声の有無、タイトル画面やシーン名の表示を選べます。できあがったムービーは、写真ライブラリへ保存したり共有したりできます。YouTube の概要欄に貼れる目次のコピーにも対応。設定は次回にも引き継がれます。

元の写真・動画は安全
Splice は写真や動画を変更・削除しません。ムービーから外しても、写真ライブラリには残ります。

プライバシー
アカウント登録・広告・アプリ内課金・トラッキングはありません。処理はすべて iPhone の中で行い、素材をどこにもアップロードしません。シーン名には写真の位置情報から地名を取得する Apple の機能を使うため、通信が必要です。

日本語と English に対応。iOS 17 以降が必要です。
```

### このバージョンの最新情報 (1.0)

```
初回リリースです。
```

### 審査メモ

```
写真ライブラリへのアクセスは、ユーザーが選んだ写真・動画の読み込みと、書き出したムービーの保存にだけ使います。アカウント登録は不要で、開発者へデータは送信されません。動作確認の手順: 最初の画面の + → 「期間を選んで作成」→ 写真・動画のある期間を選び「この期間で作成」。シーン名は端末内の逆ジオコーディング(写真の位置情報から地名を取得)で付くため、ネット接続が必要です。
```

---

## 計測コマンド

```sh
python3 - <<'PY'
import re
doc = open('AppStore/metadata.md').read()
for head, body in re.findall(r'\n### (.+?)\n\n```\n(.*?)\n```\n', doc, re.S):
    print(f'{len(body):5d}  {head}')
PY
```
