# App Store 提出素材

```
metadata.md                      全テキスト項目(日英)と審査メモ。コードブロックがそのまま入力値
screenshots/
  captions.json                  スクショの見出し・説明文(日英)
  raw/<ja|en>/<id>.png           シミュレータの素の画面(iPhone 17 Pro Max、1320x2868)
  final/<サイズ>/<ja|en-US>/     上に説明文を載せた完成品。これをアップロードする
Scripts/appstore_shots.py        raw + captions.json → final
```

アップロード先(App Store Connect の iPhone スロット。小さい画面は大きい方から自動で縮小される):

| スロット | 場所 | サイズ |
|---|---|---|
| Dynamic Island (medium) — **提出に必須** | `final/1206x2622/<ja\|en-US>/` | 1206 × 2622 |
| Dynamic Island (large) | `final/1320x2868/<ja\|en-US>/` | 1320 × 2868 |

iPad・Apple Watch・Mac・Vision・Duo などは、このアプリが対応していないので用意しない。

## スクショの撮り直し

1. 素材入りのシミュレータを用意する(撮影日 2026-10-10〜12 の写真 23 枚と動画 4 本。EXIF の日時・位置情報つき)。
   `xcrun simctl addmedia <UDID> *.jpg *.mp4`。素材は写真アプリ側にあれば何でもよいが、`ScreenshotTests` は 10/10〜10/12 を選ぶ。
2. `xcrun simctl privacy <UDID> reset photos com.jonki.splice`(許可アラートを `ScreenshotTests` が押すため)。
3. 言語ごとに `projects.json` を消してから撮る(一覧に前の言語のムービーが残らないように):

```sh
for t in testJapanese testEnglish; do
  rm -f "$(xcrun simctl get_app_container <UDID> com.jonki.splice data)/Documents/projects.json"
  SCREENSHOT_DIR=/tmp/splice-shots xcodebuild test -project Splice.xcodeproj -scheme Screenshots \
    -only-testing:SpliceUITests/ScreenshotTests/$t -destination 'id=<UDID>' -derivedDataPath build
done
```

4. `/tmp/splice-shots/<ja|en>/*.png` を `raw/` にコピーし、`pip install pillow` した Python で `python3 Scripts/appstore_shots.py`。

`Screenshots` スキームは撮影専用で、通常の `Splice` スキームのテストには入らない。
