import AVFoundation
import Foundation
import UIKit

nonisolated final class RecordingStore: @unchecked Sendable {
    static let shared = RecordingStore()

    struct SessionURLs {
        let directory: URL
        let landscape: URL
        let portrait: URL
        let thumbnail: URL
        let meta: URL
    }

    private let baseURL: URL
    private let fm = FileManager.default

    init() {
        let docs = try! fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        baseURL = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - URL helpers

    func directory(for id: UUID) -> URL {
        baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func allocateSession(id: UUID) throws -> SessionURLs {
        let dir = directory(for: id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return SessionURLs(
            directory: dir,
            landscape: dir.appendingPathComponent("landscape.mov"),
            portrait: dir.appendingPathComponent("portrait.mov"),
            thumbnail: dir.appendingPathComponent("thumbnail.jpg"),
            meta: dir.appendingPathComponent("meta.json")
        )
    }

    func landscapeURL(for session: RecordingSession) -> URL? {
        guard session.hasLandscape else { return nil }
        let url = directory(for: session.id).appendingPathComponent("landscape.mov")
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func portraitURL(for session: RecordingSession) -> URL? {
        guard session.hasPortrait else { return nil }
        let url = directory(for: session.id).appendingPathComponent("portrait.mov")
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnailURL(for session: RecordingSession) -> URL {
        directory(for: session.id).appendingPathComponent("thumbnail.jpg")
    }

    // MARK: - Meta + lifecycle

    func writeMeta(for session: RecordingSession) throws {
        let metaURL = directory(for: session.id).appendingPathComponent("meta.json")
        let data = try JSONEncoder().encode(session)
        try data.write(to: metaURL, options: .atomic)
    }

    func loadAllSessions() -> [RecordingSession] {
        let entries = (try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        return entries.compactMap { url in
            let metaURL = url.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL) else { return nil }
            return try? dec.decode(RecordingSession.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(session: RecordingSession) throws {
        try fm.removeItem(at: directory(for: session.id))
    }

    // MARK: - Storage info

    /// Total bytes used by all recording sessions (videos + thumbnails + metas).
    func totalUsedBytes() -> Int64 {
        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Bytes still available on the device's primary volume.
    func availableDeviceBytes() -> Int64 {
        let attrs = try? fm.attributesOfFileSystem(forPath: baseURL.path)
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Thumbnail generation

    /// Renders a single first-frame thumbnail (~320pt wide) as JPEG to
    /// `<sessionDir>/thumbnail.jpg`. Best-effort: silently no-ops on failure
    /// or after a 3-second timeout (a corrupted file or slow storage shouldn't
    /// keep the post-recording UI waiting indefinitely).
    func generateThumbnail(for session: RecordingSession) async {
        let videoURL: URL? = landscapeURL(for: session) ?? portraitURL(for: session)
        guard let videoURL else { return }

        let outputURL = thumbnailURL(for: session)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await Self.renderThumbnail(from: videoURL, to: outputURL)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
            }
            await group.next()
            group.cancelAll()
        }
    }

    private static func renderThumbnail(from videoURL: URL, to outputURL: URL) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        do {
            let time = CMTime(seconds: 0.2, preferredTimescale: 600)
            let cgImage = try await generator.image(at: time).image
            try Task.checkCancellation()
            let uiImage = UIImage(cgImage: cgImage)
            if let data = uiImage.jpegData(compressionQuality: 0.7) {
                try? data.write(to: outputURL, options: .atomic)
            }
        } catch {
            // best effort — timeout cancellation lands here too
        }
    }
}
