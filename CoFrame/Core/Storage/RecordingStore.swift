import Foundation

nonisolated final class RecordingStore: @unchecked Sendable {
    static let shared = RecordingStore()

    struct SessionURLs {
        let directory: URL
        let landscape: URL
        let portrait: URL
        let meta: URL
    }

    private let baseURL: URL
    private let fm = FileManager.default

    init() {
        let docs = try! fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        baseURL = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func allocateSession(id: UUID) throws -> SessionURLs {
        let dir = baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return SessionURLs(
            directory: dir,
            landscape: dir.appendingPathComponent("landscape.mov"),
            portrait: dir.appendingPathComponent("portrait.mov"),
            meta: dir.appendingPathComponent("meta.json")
        )
    }

    func writeMeta(for session: RecordingSession) throws {
        let dir = baseURL.appendingPathComponent(session.id.uuidString, isDirectory: true)
        let metaURL = dir.appendingPathComponent("meta.json")
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
        let dir = baseURL.appendingPathComponent(session.id.uuidString, isDirectory: true)
        try fm.removeItem(at: dir)
    }
}
