//
//  Localization.swift
//  Dual
//
//  Created by Codex on 2026/3/25.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var displayNameKey: String {
        switch self {
        case .system:
            return "language.option.system"
        case .english:
            return "language.option.english"
        case .simplifiedChinese:
            return "language.option.simplifiedChinese"
        }
    }

    static func resolve(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .system
    }
}

enum L10n {
    private static let tableName = "Localizable"

    static func string(_ key: String, localeIdentifier: String? = nil, _ arguments: CVarArg...) -> String {
        string(key, localeIdentifier: localeIdentifier, arguments: arguments)
    }

    static func string(_ key: String, localeIdentifier: String? = nil, arguments: [CVarArg]) -> String {
        let bundle = Bundle.localizedBundle(for: localeIdentifier)
        let format = NSLocalizedString(key, tableName: tableName, bundle: bundle, value: key, comment: "")

        guard !arguments.isEmpty else {
            return format
        }

        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        return String(format: format, locale: locale, arguments: arguments)
    }
}

private extension Bundle {
    static func localizedBundle(for localeIdentifier: String?) -> Bundle {
        guard let localeIdentifier else {
            return .main
        }

        let candidates = Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: [localeIdentifier]
        ) + [localeIdentifier]

        for candidate in candidates {
            guard let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else {
                continue
            }
            return bundle
        }

        return .main
    }
}
