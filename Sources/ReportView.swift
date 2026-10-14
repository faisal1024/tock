import Charts
import SwiftUI
import UniformTypeIdentifiers

enum ReportRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case week = "This Week"
    case lastWeek = "Last Week"
    case month = "This Month"
    case lastMonth = "Last Month"
    case all = "All Time"

    var id: String { rawValue }

    func interval(sessions: [Session], now: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        switch self {
        case .today: return cal.dateInterval(of: .day, for: now)!
        case .yesterday: return cal.dateInterval(of: .day, for: cal.date(byAdding: .day, value: -1, to: now)!)!
        case .week: return cal.dateInterval(of: .weekOfYear, for: now)!
        case .lastWeek: return cal.dateInterval(of: .weekOfYear, for: cal.date(byAdding: .day, value: -7, to: now)!)!
        case .month: return cal.dateInterval(of: .month, for: now)!
        case .lastMonth: return cal.dateInterval(of: .month, for: cal.date(byAdding: .month, value: -1, to: now)!)!
        case .all:
            let first = sessions.map(\.start).min() ?? now
            return DateInterval(start: cal.startOfDay(for: first), end: cal.dateInterval(of: .day, for: now)!.end)
        }
    }

    var isSingleDay: Bool { self == .today || self == .yesterday }
}

private struct TagTotal: Identifiable {
    var tag: String
    var seconds: TimeInterval
    var count: Int
    var id: String { tag }
}

private struct DayTagRow: Identifiable {
    var day: Date
    var tag: String
    var minutes: Double
    var id: String { "\(day.timeIntervalSince1970)-\(tag)" }
}

struct ReportView: View {
    @EnvironmentObject var store: Store
    @AppStorage("reportRange") private var range: ReportRange = .week
    @State private var selection = Set<UUID>()
    @State private var copied = false

    private var interval: DateInterval { range.interval(sessions: store.sessions) }

    private var sessions: [Session] {
        store.sessions.filter { interval.contains($0.start) }.sorted { $0.start > $1.start }
    }

    private var total: TimeInterval { sessions.reduce(0) { $0 + TimeInterval($1.focusedSeconds) } }

    /// Time per tag. A session with several tags has its time split evenly so totals add up.
    private var tagTotals: [TagTotal] {
        var secs: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]
        for s in sessions {
            let tags = s.tags.isEmpty ? ["untagged"] : s.tags
            for t in tags {
                secs[t, default: 0] += TimeInterval(s.focusedSeconds) / Double(tags.count)
                counts[t, default: 0] += 1
            }
        }
        return secs.map { TagTotal(tag: $0.key, seconds: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var useMonths: Bool { interval.duration > 62 * 86400 }

    private var dayRows: [DayTagRow] {
        let cal = Calendar.current
        var map: [String: DayTagRow] = [:]
        for s in sessions {
            let day = useMonths ? cal.dateInterval(of: .month, for: s.start)!.start : cal.startOfDay(for: s.start)
            let tags = s.tags.isEmpty ? ["untagged"] : s.tags
            for t in tags {
                let key = "\(day.timeIntervalSince1970)-\(t)"
                map[key, default: DayTagRow(day: day, tag: t, minutes: 0)].minutes +=
                    Double(s.focusedSeconds) / 60 / Double(tags.count)
            }
        }
        return map.values.sorted { $0.day < $1.day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if sessions.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "timer",
                                       description: Text("Nothing logged for \(range.rawValue.lowercased())."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summaryCards
                HStack(alignment: .top, spacing: 16) {
                    tagChart.frame(minWidth: 280)
                    if !range.isSingleDay { dayChart }
                }
                .frame(height: 220)
                sessionTable
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        HStack {
            Picker("", selection: $range) {
                ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)

            Spacer()

            Button {
                copySummary()
            } label: {
                Label(copied ? "Copied" : "Copy Summary", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(sessions.isEmpty)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(sessions.isEmpty)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(title: "Focused", value: Fmt.duration(total))
            StatCard(title: "Sessions", value: "\(sessions.count)")
            StatCard(title: "Completed", value: "\(sessions.filter(\.completed).count)")
            if !range.isSingleDay {
                let days = Set(sessions.map { Calendar.current.startOfDay(for: $0.start) }).count
                StatCard(title: "Avg / active day", value: Fmt.duration(days > 0 ? total / Double(days) : 0))
            }
        }
    }

    private var tagChart: some View {
        GroupBox("By tag") {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tagTotals) { t in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(t.tag == "untagged" ? "untagged" : "#\(t.tag)")
                                    .foregroundStyle(t.tag == "untagged" ? .secondary : .primary)
                                Spacer()
                                Text(Fmt.duration(t.seconds)).monospacedDigit()
                                Text(total > 0 ? "\(Int((t.seconds / total * 100).rounded()))%" : "")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .font(.callout)
                            GeometryReader { geo in
                                Capsule().fill(Color.primary.opacity(0.07))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.accentColor)
                                            .frame(width: geo.size.width * (tagTotals.first.map { t.seconds / $0.seconds } ?? 0))
                                    }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private var dayChart: some View {
        GroupBox(useMonths ? "By month" : "By day") {
            Chart(dayRows) { row in
                BarMark(
                    x: .value("Day", row.day, unit: useMonths ? .month : .day),
                    y: .value("Minutes", row.minutes)
                )
                .foregroundStyle(by: .value("Tag", row.tag))
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let m = value.as(Double.self) { Text(Fmt.duration(m * 60)) }
                    }
                }
            }
            .chartLegend(position: .bottom)
            .padding(4)
        }
    }

    private var sessionTable: some View {
        Table(sessions, selection: $selection) {
            TableColumn("When") { s in
                Text(s.start.formatted(range.isSingleDay ? .dateTime.hour().minute()
                                                         : .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 160)
            TableColumn("Focused") { s in
                HStack(spacing: 4) {
                    Text(Fmt.duration(TimeInterval(s.focusedSeconds))).monospacedDigit()
                    if !s.completed {
                        Image(systemName: "stop.circle").foregroundStyle(.secondary).help("Finished early")
                    }
                }
            }
            .width(min: 70, ideal: 80)
            TableColumn("Tags") { s in Text(s.tagLabel).foregroundStyle(Color.accentColor) }
                .width(min: 80, ideal: 140)
            TableColumn("Note") { s in Text(s.note) }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Delete \(ids.count == 1 ? "Session" : "\(ids.count) Sessions")", role: .destructive) {
                store.delete(ids: ids)
            }
            .disabled(ids.isEmpty)
        }
        .onDeleteCommand { store.delete(ids: selection) }
    }

    // MARK: Actions

    private func copySummary() {
        let df = DateIntervalFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let end = interval.end.addingTimeInterval(-1)
        var lines = ["Focus report — \(range.rawValue) (\(df.string(from: interval.start, to: end)))",
                     "Total: \(Fmt.duration(total)) across \(sessions.count) sessions", ""]
        for t in tagTotals {
            let name = t.tag == "untagged" ? "untagged" : "#\(t.tag)"
            lines.append("• \(name): \(Fmt.duration(t.seconds))")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tock-\(range.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var rows = ["start,end,focused_minutes,planned_minutes,completed,tags,note"]
        for s in sessions.reversed() {
            rows.append([
                iso.string(from: s.start), iso.string(from: s.end),
                String(format: "%.1f", Double(s.focusedSeconds) / 60),
                String(format: "%.1f", Double(s.plannedSeconds) / 60),
                s.completed ? "yes" : "no",
                esc(s.tags.joined(separator: " ")), esc(s.note),
            ].joined(separator: ","))
        }
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct StatCard: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
