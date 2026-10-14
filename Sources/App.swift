import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UserNotifications

@main
@MainActor
enum TockMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    lazy var engine = TimerEngine(store: store)

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var reportWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.animates = false

        engine.$remaining.combineLatest(engine.$phase)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        updateStatusItem()

        // ⌃⌥T opens Tock from anywhere.
        HotKey.register(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.togglePopover()
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let breakAction = UNNotificationAction(identifier: TimerEngine.startBreakAction,
                                               title: "Start \(TimerEngine.breakMinutes)-min Break")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: TimerEngine.notificationCategory, actions: [breakAction], intentIdentifiers: []),
        ])

        let args = ProcessInfo.processInfo.arguments
        if args.contains("-startDemo") { engine.draft = "#client-a draft spec"; engine.start() }
        if args.contains("-offerBreak") { engine.breakOffered = true }
        if args.contains("-breakDemo") { engine.startBreak() }
        if args.contains("-showPopover") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePopover() } }
        if args.contains("-showReport") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showReport() } }
        if let i = args.firstIndex(of: "-snapshot"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.snapshot(to: dir) }
        }
    }

    /// Test aid: writes PNGs of the open popover / report window, then quits.
    private func snapshot(to dir: URL) {
        func save(_ view: NSView?, _ name: String) {
            guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        save(popover.contentViewController?.view.window?.contentView?.superview, "popover.png")
        save(reportWindow?.contentView?.superview, "report.png")
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch engine.phase {
        case .idle: symbol = "timer"
        case .running: symbol = engine.isBreak ? "cup.and.saucer" : "circle.dotted.circle"
        case .paused: symbol = "pause.circle"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tock")
        if engine.phase == .idle {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = NSAttributedString(string: " " + Fmt.clock(engine.remaining), attributes: [.font: font])
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        // Fresh view each time so the text field grabs focus on open.
        let root = PopoverView(
            openReport: { [weak self] in self?.showReport() },
            close: { [weak self] in self?.popover.performClose(nil) }
        )
        .environmentObject(store)
        .environmentObject(engine)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showReport() {
        popover.performClose(nil)
        if reportWindow == nil {
            let host = NSHostingController(rootView: ReportView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Tock Report"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 860, height: 640))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("TockReport")
            reportWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        reportWindow?.makeKeyAndOrderFront(nil)
    }

    // Show the "time's up" banner even though Tock is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // "Start Break" button on the notification starts the break; clicking the notification itself opens Tock.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if action == TimerEngine.startBreakAction {
                    self.engine.startBreak()
                } else if action == UNNotificationDefaultActionIdentifier, !self.popover.isShown {
                    self.togglePopover()
                }
            }
        }
        completionHandler()
    }
}

/// Minimal global hotkey via Carbon (no Accessibility permission needed).
enum HotKey {
    nonisolated(unsafe) private static var handler: (() -> Void)?
    nonisolated(unsafe) private static var ref: EventHotKeyRef?

    static func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        self.handler = { MainActor.assumeIsolated { handler() } }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.handler?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x544F_434B), id: 1) // 'TOCK'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
