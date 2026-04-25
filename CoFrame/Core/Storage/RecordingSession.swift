import Foundation

nonisolated struct RecordingSession: Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let quality: VideoQuality
    let landscapeURL: URL?
    let portraitURL: URL?
    var durationSeconds: Double
}
