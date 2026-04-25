import AVFoundation
import Foundation

nonisolated enum VideoQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case hd1080p30
    case uhd4K30
    case uhd4K60

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hd1080p30: "1080p"
        case .uhd4K30:   "4K30"
        case .uhd4K60:   "4K60"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080p30: .hd1920x1080
        case .uhd4K30, .uhd4K60: .hd4K3840x2160
        }
    }

    var landscapeSize: CGSize {
        switch self {
        case .hd1080p30: CGSize(width: 1920, height: 1080)
        case .uhd4K30, .uhd4K60: CGSize(width: 3840, height: 2160)
        }
    }

    /// Center-cropped 9:16 portrait derived from the landscape source. Width rounded to even pixels for encoder friendliness.
    var portraitSize: CGSize {
        let h = landscapeSize.height
        let rawW = h * 9.0 / 16.0
        let w = (rawW / 2.0).rounded(.down) * 2.0
        return CGSize(width: w, height: h)
    }

    var frameRate: Int32 {
        switch self {
        case .hd1080p30, .uhd4K30: 30
        case .uhd4K60: 60
        }
    }

    var landscapeBitrate: Int {
        switch self {
        case .hd1080p30: 12_000_000
        case .uhd4K30:   50_000_000
        case .uhd4K60:   80_000_000
        }
    }

    var portraitBitrate: Int { landscapeBitrate * 4 / 10 }
}
