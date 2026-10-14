import Foundation

/// One logged focus session.
struct Session: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    /// Seconds actually spent focusing (excludes paused time).
    var focusedSeconds: Int
    var plannedSeconds: Int
    var tags: [String]
    var note: String
    var completed: Bool

    var tagLabel: String { tags.isEmpty ? "" : tags.map { "#\($0)" }.joined(separator: " ") }
}

/// Parses quick-entry text like `45 #client-a draft proposal` or `#writing 1h chapter 3`.
/// - A plain number as the first word, or `30m` / `1h` / `1.5h` anywhere, sets the duration.
/// - Words starting with `#` become tags.
/// - Everything else is the note.
struct ParsedInput: Equatable {
    var minutes: Int?
    var tags: [String]
    var note: String
}

enum InputParser {
    static func parse(_ text: String) -> ParsedInput {
        var minutes: Int?
        var tags: [String] = []
        var words: [String] = []
        for raw in text.split(whereSeparator: \.isWhitespace) {
            let token = String(raw)
            if token.hasPrefix("#") {
                let tag = token.drop(while: { $0 == "#" }).lowercased()
                if !tag.isEmpty, !tags.contains(tag) { tags.append(tag) }
                continue
            }
            if minutes == nil, let m = duration(token, allowBare: words.isEmpty) {
                minutes = m
                continue
            }
            words.append(token)
        }
        return ParsedInput(minutes: minutes, tags: tags, note: words.joined(separator: " "))
    }

    private static func duration(_ token: String, allowBare: Bool) -> Int? {
        let t = token.lowercased()
        func valid(_ n: Int) -> Int? { (1...600).contains(n) ? n : nil }
        if allowBare, let n = Int(t) { return valid(n) }
        for suffix in ["mins", "min", "m"] where t.hasSuffix(suffix) {
            if let n = Int(t.dropLast(suffix.count)) { return valid(n) }
        }
        for suffix in ["hrs", "hr", "h"] where t.hasSuffix(suffix) {
            if let h = Double(t.dropLast(suffix.count)) { return valid(Int((h * 60).rounded())) }
        }
        return nil
    }
}

enum Fmt {
    /// 25:00 or 1:05:00
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// 2h 15m / 45m / 0m
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMin = Int((seconds / 60).rounded())
        let h = totalMin / 60, m = totalMin % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
