import AppKit
import Foundation
import UserNotifications

@MainActor
final class TimerEngine: ObservableObject {
    enum Phase { case idle, running, paused }

    @Published private(set) var phase: Phase = .idle
    @Published var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: "minutes") }
    }
    @Published var draft: String = "" {
        didSet {
            // Typing a duration ("45", "1h") into the box updates the dial,
            // but only when that typed duration changes, so ▲▼ still work afterwards.
            let new = InputParser.parse(draft).minutes
            if new != InputParser.parse(oldValue).minutes, let new { minutes = new }
        }
    }
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var planned: TimeInterval = 0
    @Published private(set) var tags: [String] = []
    @Published private(set) var note: String = ""
    /// True while the current countdown is a break (never logged as focus time).
    @Published private(set) var isBreak = false
    /// Set when a focus session completes; the popover offers a break but never starts one on its own.
    @Published var breakOffered = false

    static let breakMinutes = 5
    static let notificationCategory = "FOCUS_DONE"
    static let startBreakAction = "START_BREAK"

    private let store: Store
    private var startDate: Date?
    private var endDate: Date?
    private var focusedBefore: TimeInterval = 0
    private var segmentStart: Date?
    private var ticker: Timer?

    init(store: Store) {
        self.store = store
        let saved = UserDefaults.standard.integer(forKey: "minutes")
        minutes = saved > 0 ? saved : 25
    }

    var progress: Double { planned > 0 ? min(1, max(0, 1 - remaining / planned)) : 0 }

    // MARK: Controls

    /// ▲▼ buttons and arrow keys. Before starting this changes the length; while running it extends/shortens.
    func adjust(_ deltaMinutes: Int) {
        switch phase {
        case .idle:
            minutes = min(max(minutes + deltaMinutes, 1), 480)
        case .running, .paused:
            var newRemaining = remaining + TimeInterval(deltaMinutes * 60)
            // Never let a "−" click end the session by accident; floor at 1 minute.
            if newRemaining < 60 { newRemaining = min(remaining, 60) }
            planned += newRemaining - remaining
            remaining = newRemaining
            if phase == .running { endDate = Date().addingTimeInterval(remaining) }
        }
    }

    func start() {
        guard phase == .idle else { return }
        let parsed = InputParser.parse(draft)
        tags = parsed.tags
        note = parsed.note
        isBreak = false
        breakOffered = false
        begin(seconds: TimeInterval(minutes * 60))
    }

    /// Optional break, only ever started by the user (popover button or notification action).
    func startBreak() {
        guard phase == .idle else { return }
        tags = []
        note = ""
        isBreak = true
        breakOffered = false
        begin(seconds: TimeInterval(Self.breakMinutes * 60))
    }

    private func begin(seconds: TimeInterval) {
        planned = seconds
        remaining = planned
        let now = Date()
        startDate = now
        focusedBefore = 0
        segmentStart = now
        endDate = now.addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    func togglePause() {
        phase == .running ? pause() : resume()
    }

    func pause() {
        guard phase == .running, let seg = segmentStart, let end = endDate else { return }
        let now = Date()
        focusedBefore += now.timeIntervalSince(seg)
        remaining = max(0, end.timeIntervalSince(now))
        segmentStart = nil
        endDate = nil
        phase = .paused
        ticker?.invalidate()
    }

    func resume() {
        guard phase == .paused else { return }
        let now = Date()
        segmentStart = now
        endDate = now.addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    /// Stop early. Saves the session if at least a minute of focus was logged.
    func finishEarly() {
        guard phase != .idle else { return }
        let logged = !isBreak && focusedSeconds >= 60
        if logged { record(completed: false) }
        reset()
        breakOffered = logged
    }

    func discard() { reset() }

    // MARK: Internals

    private var focusedSeconds: TimeInterval {
        focusedBefore + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
        tick()
    }

    private func tick() {
        guard phase == .running, let end = endDate else { return }
        let r = max(0, end.timeIntervalSinceNow)
        remaining = r
        if r <= 0 { complete() }
    }

    private func complete() {
        if isBreak {
            reset()
            notifyBreakOver()
            return
        }
        let session = record(completed: true)
        reset()
        breakOffered = true
        notify(session)
    }

    @discardableResult
    private func record(completed: Bool) -> Session {
        let session = Session(
            start: startDate ?? Date(),
            end: Date(),
            focusedSeconds: Int(focusedSeconds.rounded()),
            plannedSeconds: Int(planned.rounded()),
            tags: tags,
            note: note,
            completed: completed
        )
        store.add(session)
        return session
    }

    private func reset() {
        ticker?.invalidate()
        ticker = nil
        phase = .idle
        startDate = nil
        endDate = nil
        segmentStart = nil
        focusedBefore = 0
        remaining = 0
        planned = 0
        tags = []
        note = ""
        isBreak = false
    }

    private func notify(_ session: Session) {
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = "Time's up — \(Fmt.duration(TimeInterval(session.focusedSeconds))) done"
        let detail = [session.tagLabel, session.note].filter { !$0.isEmpty }.joined(separator: " · ")
        content.body = detail.isEmpty ? "Nice work." : detail
        content.categoryIdentifier = Self.notificationCategory
        let request = UNNotificationRequest(identifier: session.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func notifyBreakOver() {
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = "Break's over"
        content.body = "Ready for the next session?"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
