import Foundation

/// Every interface string goes through `L`. The language is chosen from the menu
/// bar and kept in the defaults; English until the user picks another.
/// Adding a language is adding an .lproj folder and a line to `supported`.
enum Localization {
    struct Language: Equatable {
        let code: String
        /// The name as its own speakers write it: that is how the menu lists it.
        let name: String
    }

    static let supported = [Language(code: "en", name: "English"),
                            Language(code: "ru", name: "Русский"),
                            Language(code: "es", name: "Español")]
    static let fallback = "en"
    static let defaultsKey = "language"
    /// Posted after the language changed, so what is already on screen can be redrawn.
    static let didChange = Notification.Name("ConservaLanguageDidChange")

    /// SwiftPM puts resources in Conserva_Conserva.bundle. In the .app it sits in
    /// Contents/Resources; `swift run` keeps it next to the binary.
    static let resources: Bundle = {
        let name = "Conserva_Conserva.bundle"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
                          Bundle.main.bundleURL.appendingPathComponent(name),
                          Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name)]
        for url in candidates.compactMap({ $0 }) {
            if let b = Bundle(url: url) { return b }
        }
        return Bundle.main
    }()

    private(set) static var code: String = stored()
    private(set) static var bundle: Bundle = bundle(for: code)

    static var locale: Locale { Locale(identifier: code) }

    static func set(_ code: String) {
        guard supported.contains(where: { $0.code == code }), code != self.code else { return }
        UserDefaults.standard.set(code, forKey: defaultsKey)
        self.code = code
        bundle = bundle(for: code)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func stored() -> String {
        let code = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
        return supported.contains(where: { $0.code == code }) ? code : fallback
    }

    private static func bundle(for code: String) -> Bundle {
        if let path = resources.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) { return b }
        return resources
    }
}

func L(_ key: String) -> String {
    Localization.bundle.localizedString(forKey: key, value: key, table: nil)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Localization.locale, arguments: args)
}
