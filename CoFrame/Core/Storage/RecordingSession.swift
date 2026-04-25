import Foundation

/// Persisted metadata for one recording session. Files (`landscape.mov`, `portrait.mov`,
/// `thumbnail.jpg`) live in the store's per-session directory, addressed by `id`.
/// Absolute URLs are intentionally **not** stored here — the app container path can
/// change between launches/updates, so we always reconstruct paths via `RecordingStore`.
nonisolated struct RecordingSession: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let createdAt: Date
    let quality: VideoQuality
    let hasLandscape: Bool
    let hasPortrait: Bool
    var durationSeconds: Double
    var landscapeBytes: Int64
    var portraitBytes: Int64

    var totalBytes: Int64 { landscapeBytes + portraitBytes }
}
