import Foundation

public enum L10n {
    private static let english = Bundle.main.object(forInfoDictionaryKey: "OpenWiloLanguage") as? String == "en"
    private static let translations = english
        ? Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        : nil

    public static let locale = Locale(identifier: english ? "en" : "zh_CN")

    public static func text(_ key: String) -> String {
        translations?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    public static func networkValue(_ value: String) -> String {
        switch value {
        case "未知", "开放": return text(value)
        default: return value
        }
    }
}
