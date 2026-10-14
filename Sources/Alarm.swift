import AppKit

/// Plays the chosen alarm sound on repeat for a set number of seconds, or until stopped.
@MainActor
final class Alarm: NSObject, NSSoundDelegate {
    static let shared = Alarm()

    static let soundKey = "alarmSound"
    static let ringSecondsKey = "ringSeconds"
    static let none = "None"
    static let defaultSound = "Glass"
    static let defaultRingSeconds = 10
    static let ringOptions = [0, 5, 10, 20, 30, 60] // 0 = play once

    /// Built-in macOS alert sounds (from /System/Library/Sounds).
    static let sounds: [String] = {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let found = names.map { ($0 as NSString).deletingPathExtension }.sorted()
        return found.isEmpty ? [defaultSound] : found
    }()

    static var soundName: String {
        UserDefaults.standard.string(forKey: soundKey) ?? defaultSound
    }

    static var ringSeconds: Int {
        UserDefaults.standard.object(forKey: ringSecondsKey) as? Int ?? defaultRingSeconds
    }

    static func ringLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Once" : seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) minute"
    }

    private var sound: NSSound?
    private var until: Date?

    var isRinging: Bool { until != nil }

    func ring() {
        stop()
        let name = Self.soundName
        guard name != Self.none, let s = NSSound(named: NSSound.Name(name)) else { return }
        until = Date().addingTimeInterval(TimeInterval(Self.ringSeconds))
        s.delegate = self
        sound = s
        s.play()
    }

    /// Plays one chime so the user can hear a sound when picking it.
    func preview(_ name: String) {
        stop()
        guard name != Self.none else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    func stop() {
        until = nil
        sound?.stop()
        sound = nil
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        MainActor.assumeIsolated {
            guard finished, sound === self.sound, let until, Date() < until else {
                if sound === self.sound { self.until = nil; self.sound = nil }
                return
            }
            // Short gap between chimes so it sounds like a ring, not a drone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                MainActor.assumeIsolated {
                    if self.sound === sound, self.isRinging { sound.play() }
                }
            }
        }
    }
}
