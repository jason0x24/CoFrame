import Foundation

/// Static accessors for user-tunable defaults persisted in `UserDefaults`.
/// Currently only the most-recent capture choices are remembered; the recording
/// UI's chip row writes to these via `didSet`, so users never have to set them
/// in a settings page.
enum AppPreferences {
    enum Key {
        static let defaultQuality   = "cf.defaultQuality"
        static let defaultGuideLine = "cf.defaultGuideLine"
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
}
