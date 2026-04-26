import Foundation

/// User-tunable defaults persisted in `UserDefaults`. Capture-side defaults
/// (quality / guide line) are written automatically by the recording UI's
/// chip row via `didSet`; the language override is set from `SettingsView`.
enum AppPreferences {
    enum Key {
        static let defaultQuality   = "cf.defaultQuality"
        static let defaultGuideLine = "cf.defaultGuideLine"
        static let language         = "cf.language"
    }

    private static let store = UserDefaults.standard

    static var defaultQuality: VideoQuality {
        get {
            let raw = store.string(forKey: Key.defaultQuality)
            return raw.flatMap(VideoQuality.init(rawValue:)) ?? .hd1080p30
        }
        set { store.set(newValue.rawValue, forKey: Key.defaultQuality) }
    }

    static var defaultGuideLine: GuideLineKind {
        get {
            let raw = store.string(forKey: Key.defaultGuideLine)
            return raw.flatMap(GuideLineKind.init(rawValue:)) ?? .ruleOfThirds
        }
        set { store.set(newValue.rawValue, forKey: Key.defaultGuideLine) }
    }

    static var language: LanguageOption {
        get {
            let raw = store.string(forKey: Key.language)
            return raw.flatMap(LanguageOption.init(rawValue:)) ?? .system
        }
        set { store.set(newValue.rawValue, forKey: Key.language) }
    }
}

/// Per-app language override applied via SwiftUI's `\.locale` environment.
/// `system` defers to the device's preferred language order; the explicit
/// options pin the UI to a specific localization regardless of system.
enum LanguageOption: String, CaseIterable, Identifiable, Sendable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    /// `nil` means "use system default" — caller should fall back to `Locale.current`.
    var locale: Locale? {
        switch self {
        case .system:  nil
        case .chinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }

    /// Localized label for the option itself.
    var displayName: String {
        switch self {
        case .system:  String(localized: "跟随系统")
        case .chinese: "中文"
        case .english: "English"
        }
    }
}
