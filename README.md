# Tock — menu-bar focus timer

A Horo-style Pomodoro timer that lives in your Mac menu bar.

## Use it
- Click the timer icon in the menu bar, or press **⌃⌥T** from anywhere.
- Type what you're doing, with tags: `#client-a draft proposal`  → press **Return**.
  - Put a duration in the text if you like: `45 #writing chapter 3`, `#deep 1.5h`, `review 30m #admin`.
- Change the length with the **▲ ▼** buttons (left = 1 min, right = 5 min),
  or the **↑ ↓** keys (±1) and **⇧↑ ⇧↓** (±5). Quick presets: 15 / 25 / 45 / 60 / 90.
- Click a recent tag chip to add or remove it.
- While running: ▲ ▼ add or remove time, **Pause/Resume** (Space), **Finish** (logs time so far), or 🗑 (discard).
- When time's up you get a sound and a notification, and the session is logged.
- **Optional 5-min break:** after a session, Tock *offers* a break (a green banner in the popover and a
  "Start 5-min Break" button on the notification). It never starts on its own. Click ✕ to skip it.
  Breaks are not logged as focus time.
- **Report** (⌘R in the popover): Today, Yesterday, This/Last Week, This/Last Month, All Time.
  Time by tag, time by day, session list (right-click to delete), **Copy Summary**, **Export CSV**.
- Gear menu: Launch at Login, Quit.

Data: `~/Library/Application Support/Tock/sessions.json`

## Build
    ./build.sh            # builds build/Tock.app
    ./build.sh --install  # also installs to /Applications and launches

Requires macOS 14+ and Xcode command-line tools (Swift 5.9+). No dependencies.

## License
MIT
