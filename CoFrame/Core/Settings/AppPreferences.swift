import AVFoundation
import Foundation

/// Static accessors for user-tunable defaults persisted in `UserDefaults`.
///
/// SwiftUI views can also bind directly via `@AppStorage(AppPreferences.Key.…)`.
/// Defaults applied on first read so existing users without saved values
/// see the v1 baseline (1080p / rule-of-thirds / mute-on).
enum AppPreferences {
    enum Key {
        static let defaultQuality       = "cf.defaultQuality"
        static let defaultGuideLine     = "cf.defaultGuideLine"
        static let muteSystemSounds     = "cf.muteSystemSounds"
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

    static var muteSystemSounds: Bool {
        get { store.object(forKey: Key.muteSystemSounds) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.muteSystemSounds) }
    }

    /// Configure the system audio session for video recording. When
    /// `muteSystemSounds` is on, other audio is *ducked* (lowered) for the
    /// duration of recording — iOS doesn't expose a way to fully silence
    /// notifications, but `.duckOthers` is the closest legitimate path.
    /// Best-effort: throws are swallowed since this is a polish concern.
    static func applyAudioSessionConfig() {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = muteSystemSounds
            ? [.duckOthers]
            : [.mixWithOthers]
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: options)
            try session.setActive(true)
        } catch {
            // ignore — best-effort
        }
    }
}
