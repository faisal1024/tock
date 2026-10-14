import Foundation

/// Persists sessions to ~/Library/Application Support/Tock/sessions.json
@MainActor
final class Store: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    let fileURL: URL

    init() {
        let dir = ProcessInfo.processInfo.environment["TOCK_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sessions.json")
        load()
    }

    func add(_ session: Session) {
        sessions.append(session)
        save()
    }

    func delete(ids: Set<UUID>) {
        sessions.removeAll { ids.contains($0.id) }
        save()
    }

    /// Most recently used tags, newest first.
    var recentTags: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in sessions.reversed() {
            for t in s.tags where !seen.contains(t) {
                seen.insert(t)
                out.append(t)
            }
            if out.count >= 8 { break }
        }
        return out
    }

    func focusedSeconds(in interval: DateInterval) -> TimeInterval {
        sessions.filter { interval.contains($0.start) }.reduce(0) { $0 + TimeInterval($1.focusedSeconds) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? decoder.decode([Session].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
