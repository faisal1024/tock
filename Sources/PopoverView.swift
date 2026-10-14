import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var engine: TimerEngine
    @EnvironmentObject var store: Store
    var openReport: () -> Void
    var close: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 14) {
            if engine.phase == .idle { idleView } else { activeView }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
    }

    // MARK: Idle — set up a new session

    private var idleView: some View {
        VStack(spacing: 12) {
            if engine.breakOffered { breakOffer }

            TextField("#tag  what are you working on?", text: $engine.draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($fieldFocused)
                .onSubmit { startAndClose() }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    let step = press.modifiers.contains(.shift) ? 5 : 1
                    engine.adjust(press.key == .upArrow ? step : -step)
                    return .handled
                }
                .onAppear { DispatchQueue.main.async { fieldFocused = true } }

            if !store.recentTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.recentTags, id: \.self) { tag in
                            Chip(text: "#\(tag)", selected: InputParser.parse(engine.draft).tags.contains(tag)) {
                                toggleTag(tag)
                            }
                        }
                    }
                }
            }

            dial(Fmt.clock(TimeInterval(engine.minutes * 60)))

            HStack(spacing: 6) {
                ForEach([15, 25, 45, 60, 90], id: \.self) { m in
                    Chip(text: "\(m)m", selected: engine.minutes == m) { engine.minutes = m }
                }
            }

            Button(action: startAndClose) {
                Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("↑↓ ±1 min   ⇧↑↓ ±5 min   ⏎ start")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Shown after a focus session ends. Nothing happens unless the user clicks.
    private var breakOffer: some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Session done").font(.callout.weight(.semibold))
                Text("Take a \(TimerEngine.breakMinutes)-min break?").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Start Break") { engine.startBreak(); close() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            Button {
                engine.breakOffered = false
            } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Skip the break")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.12)))
    }

    // MARK: Running / paused

    private var activeView: some View {
        VStack(spacing: 12) {
            if engine.isBreak {
                Label("Break", systemImage: "cup.and.saucer.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            } else if !engine.tags.isEmpty || !engine.note.isEmpty {
                HStack(spacing: 6) {
                    ForEach(engine.tags, id: \.self) { Text("#\($0)").foregroundStyle(Color.accentColor) }
                    Text(engine.note).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
            }

            dial(Fmt.clock(engine.remaining))
                .opacity(engine.phase == .paused ? 0.5 : 1)

            ProgressView(value: engine.progress)
                .tint(engine.phase == .paused ? .gray : engine.isBreak ? .green : .accentColor)

            HStack(spacing: 8) {
                Button {
                    engine.togglePause()
                } label: {
                    Label(engine.phase == .paused ? "Resume" : "Pause",
                          systemImage: engine.phase == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isBreak ? .green : .accentColor)
                .keyboardShortcut(.space, modifiers: [])

                if engine.isBreak {
                    Button {
                        engine.discard()
                    } label: {
                        Label("End Break", systemImage: "forward.end.fill").frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        engine.finishEarly()
                    } label: {
                        Label("Finish", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .help("Stop now and log the time so far")

                    Button(role: .destructive) {
                        engine.discard()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Discard this session without logging it")
                }
            }
            .controlSize(.large)
        }
    }

    // MARK: Shared pieces

    /// Big clock with ▲▼ for 1 minute on the left and 5 minutes on the right.
    private func dial(_ text: String) -> some View {
        HStack(spacing: 14) {
            Stepper2(label: "1 min", up: { engine.adjust(1) }, down: { engine.adjust(-1) })
            Text(text)
                .font(.system(size: 46, weight: .light, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 150)
            Stepper2(label: "5 min", up: { engine.adjust(5) }, down: { engine.adjust(-5) })
        }
    }

    private var footer: some View {
        HStack {
            let today = Calendar.current.dateInterval(of: .day, for: Date())!
            Label("Today \(Fmt.duration(store.focusedSeconds(in: today)))", systemImage: "sun.max")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                openReport()
            } label: {
                Label("Report", systemImage: "chart.bar.xaxis")
            }
            .keyboardShortcut("r")
            Menu {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Text("Open Tock from anywhere: ⌃⌥T")
                Divider()
                Button("Quit Tock") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    private func startAndClose() {
        engine.start()
        close()
    }

    private func toggleTag(_ tag: String) {
        var words = engine.draft.split(separator: " ").map(String.init)
        if let i = words.firstIndex(where: { $0.lowercased() == "#\(tag)" }) {
            words.remove(at: i)
        } else {
            words.insert("#\(tag)", at: 0)
        }
        engine.draft = words.joined(separator: " ") + (words.isEmpty ? "" : " ")
        fieldFocused = true
    }
}

private struct Stepper2: View {
    var label: String
    var up: () -> Void
    var down: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ArrowButton(systemImage: "chevron.up", action: up)
            Text(label).font(.caption2).foregroundStyle(.secondary).fixedSize()
            ArrowButton(systemImage: "chevron.down", action: down)
        }
    }
}

private struct ArrowButton: View {
    var systemImage: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Chip: View {
    var text: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.callout)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
                .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
