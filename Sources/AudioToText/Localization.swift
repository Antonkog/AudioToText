import Foundation
import SwiftUI
import WhisperKit

struct LocalizedMessage: Equatable {
    let key: String
    let arguments: [String]

    init(_ key: String, _ arguments: String...) {
        self.key = key
        self.arguments = arguments
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"
    case simplifiedChinese = "zh-Hans"
    case hindi = "hi"
    case arabic = "ar"
    case brazilianPortuguese = "pt-BR"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case russian = "ru"

    var id: String { rawValue }

    static var selectableLanguages: [AppLanguage] {
        [.english, .spanish, .simplifiedChinese, .hindi, .arabic, .brazilianPortuguese, .french, .german, .japanese, .russian]
    }

    var nativeName: String {
        switch self {
        case .system: ""
        case .english: "English"
        case .spanish: "Español"
        case .simplifiedChinese: "简体中文"
        case .hindi: "हिन्दी"
        case .arabic: "العربية"
        case .brazilianPortuguese: "Português (Brasil)"
        case .french: "Français"
        case .german: "Deutsch"
        case .japanese: "日本語"
        case .russian: "Русский"
        }
    }

    var effectiveLanguage: AppLanguage {
        guard self == .system else { return self }
        return Self.matchingSystemLanguage() ?? .english
    }

    var locale: Locale {
        Locale(identifier: effectiveLanguage.rawValue)
    }

    var layoutDirection: LayoutDirection {
        effectiveLanguage == .arabic ? .rightToLeft : .leftToRight
    }

    private static func matchingSystemLanguage() -> AppLanguage? {
        for identifier in Locale.preferredLanguages {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh") { return .simplifiedChinese }
            if normalized.hasPrefix("pt") { return .brazilianPortuguese }
            if let match = selectableLanguages.first(where: {
                normalized == $0.rawValue.lowercased()
                    || normalized.hasPrefix($0.rawValue.lowercased() + "-")
            }) {
                return match
            }
        }
        return nil
    }
}

enum AudioLanguageSelection: Equatable {
    case automatic
    case language(String)

    init(storedValue: String?) {
        if let storedValue, !storedValue.isEmpty, storedValue != "automatic" {
            self = .language(storedValue)
        } else {
            self = .automatic
        }
    }

    var storedValue: String {
        switch self {
        case .automatic: "automatic"
        case let .language(code): code
        }
    }

    var languageCode: String? {
        switch self {
        case .automatic: nil
        case let .language(code): code
        }
    }
}

enum AppLocalization {
    static func string(
        _ key: String,
        language: AppLanguage,
        arguments: [String] = []
    ) -> String {
        let effective = language.effectiveLanguage
        let localizedBundle = bundle(for: effective) ?? Bundle.module
        var format = localizedBundle.localizedString(forKey: key, value: nil, table: nil)

        if format == key, effective != .english, let englishBundle = bundle(for: .english) {
            format = englishBundle.localizedString(forKey: key, value: key, table: nil)
        }

        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: effective.locale, arguments: arguments)
    }

    static func string(_ message: LocalizedMessage, language: AppLanguage) -> String {
        string(message.key, language: language, arguments: message.arguments)
    }

    static var supportedAudioLanguageCodes: [String] {
        Constants.languageCodes.sorted()
    }

    static func audioLanguageName(code: String, interfaceLanguage: AppLanguage) -> String {
        let locale = interfaceLanguage.locale
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale)
            ?? code.uppercased()
    }

    static func localizedKeys(for language: AppLanguage) -> Set<String> {
        guard
            language != .system,
            let localizedBundle = bundle(for: language),
            let url = localizedBundle.url(forResource: "Localizable", withExtension: "strings"),
            let dictionary = NSDictionary(contentsOf: url) as? [String: String]
        else { return [] }
        return Set(dictionary.keys)
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        let resourceName = language.rawValue.lowercased()
        guard let path = Bundle.module.path(forResource: resourceName, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
