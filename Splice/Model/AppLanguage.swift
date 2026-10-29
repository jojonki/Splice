import Foundation
import Observation

/// アプリ内の表示言語。「システム」は端末の言語に合わせる（日本語以外は英語）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ja, en
    var id: Self { self }
}

/// 表示言語の設定。SwiftUI の文言は `\.locale` 環境値、String で作る文言は `L()` が同じ値を見る。
/// @Observable なので、View の body 内で `L()` を呼んでいれば言語切替で再描画される。
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    private static let key = "appLanguage"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init) ?? .system
    }

    /// 実際に使う言語コード（ja / en）
    var code: String {
        switch language {
        case .ja: "ja"
        case .en: "en"
        case .system: Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
        }
    }

    var locale: Locale { Locale(identifier: code) }

    var bundle: Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

/// 日本語の原文をキーにして、選択中の言語の文言を返す。`%lld` `%@` `%.1f` などの引数も受ける。
func L(_ key: String, _ args: CVarArg...) -> String {
    let settings = LanguageSettings.shared
    let format = settings.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: settings.locale, arguments: args)
}

extension Date {
    /// システムの言語ではなく、アプリで選んだ言語で日時を整形する
    func formatted(inApp style: Date.FormatStyle) -> String {
        style.locale(LanguageSettings.shared.locale).format(self)
    }
}
