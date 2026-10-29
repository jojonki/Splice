import XCTest

/// App Store 用の素材画面を撮る。通常のテストではなく、`AppStore/screenshots/README.md` の手順で
/// 素材入りのシミュレータに対して実行する(写真ライブラリが空だと途中で止まる)。
final class ScreenshotTests: XCTestCase {
    /// 撮った画像の置き場。シミュレータのアプリはホストのファイルシステムに直接書ける。
    private let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
                             ?? "/tmp/splice-shots")

    override func setUp() {
        continueAfterFailure = false
    }

    func testJapanese() throws { try capture(locale: "ja", region: "ja_JP", title: "京都・奈良・大阪の旅") }
    func testEnglish() throws { try capture(locale: "en", region: "en_US", title: "Kansai Trip") }

    private func capture(locale: String, region: String, title: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(locale))", "-AppleLocale", region]
        // 写真アクセスの確認。テスト実行のたびにアプリが入れ直され、許可が消えるのでここで許可する
        addUIInterruptionMonitor(withDescription: "photos") { alert in
            for label in ["フルアクセスを許可", "Allow Full Access", "すべての写真へのアクセスを許可", "OK"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        let dir = outDir.appendingPathComponent(locale)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func shot(_ name: String, wait: TimeInterval = 1.5) {
            Thread.sleep(forTimeInterval: wait)
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: dir.appendingPathComponent("\(name).png"))
        }

        // 一覧 → 新規作成
        app.navigationBars.buttons.element(boundBy: 1).tap()
        let titleField = app.textFields.firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", locale == "ja" ? "期間を選んで作成" : "Create from a date range"))
            .firstMatch.tap()

        // カレンダーで 10/10 → 10/12 を選ぶ
        let first = app.buttons["10"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        app.buttons["12"].tap()
        shot("calendar", wait: 2)

        // 作成 → 編集画面。逆ジオコーディングを待つ
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "この期間で作成", "Create for this range"))
            .firstMatch.tap()
        // 許可アラートは SpringBoard 側に出る
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            for label in ["フルアクセスを許可", "Allow Full Access", "すべての写真へのアクセスを許可"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
        }
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        shot("scenes", wait: 6)

        // プレビュー・トリム(先頭の素材をタップ)
        app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.2)).tap()
        shot("detail", wait: 2.5)
        app.swipeDown(velocity: .fast)

        // 書き出し
        let export = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "書き出", "Export")).firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        shot("export", wait: 1.5)
        app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "キャンセル", "Cancel")).firstMatch.tap()

        // 一覧
        app.navigationBars.buttons.element(boundBy: 0).tap()
        shot("list", wait: 1.5)

        // 使い方
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "使い方", "How to use")).firstMatch.tap()
        shot("help", wait: 1.5)
    }
}
