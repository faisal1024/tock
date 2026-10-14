# Tock — menu-bar focus timer

A Horo-style Pomodoro timer for macOS. It lives in the menu bar, starts in one keystroke,
tags your work with `#hashtags`, and gives you a time report whenever you want one.

## Install

Requires macOS 14+ and Xcode (or the Xcode command-line tools). No other dependencies.

```bash
git clone https://github.com/faisal1024/tock.git
cd tock
./build.sh --install   # builds, copies to /Applications, and launches
```

`./build.sh` on its own just builds `build/Tock.app` without installing.

## Start a timer

1. Click the timer icon in the menu bar, or press **⌃⌥T** (Control-Option-T) from any app.
2. Type what you're working on, with tags: `#client-a draft proposal`
3. Press **Return**. The countdown shows in the menu bar.

You can also put the length in the text:

| You type | Length | Tags | Note |
|---|---|---|---|
| `#client-a draft proposal` | current dial | client-a | draft proposal |
| `45 #writing chapter 3` | 45 min | writing | chapter 3 |
| `#deep 1.5h` | 90 min | deep | — |
| `review 30m #admin #email` | 30 min | admin, email | review |

Tags are not case-sensitive. Recently used tags show as chips; click one to add or remove it.

## Change the time

| Control | Effect |
|---|---|
| **▲ ▼** on the left | ±1 minute |
| **▲ ▼** on the right | ±5 minutes |
| **↑ ↓** keys | ±1 minute |
| **⇧↑ ⇧↓** keys | ±5 minutes |
| 15 / 25 / 45 / 60 / 90 chips | jump to that length |

The arrows also work **while a timer is running**, to add or remove time. A "−" click never ends
the session by accident; time floors at 1 minute.

## While a timer runs

- **Pause / Resume**: Space bar
- **Finish**: stop now and log the time so far (only if at least 1 minute was focused)
- **🗑**: discard without logging

When the time is up you hear a sound, get a notification, and the session is logged.

## Optional 5-minute break

Breaks never start on their own. Start one only when you want it:

- **5m Break** button next to **Start**, always available.
- After a session ends (or you click **Finish**), a green **"Session done — take a 5-min break?"**
  banner offers **Start Break**. Click **✕** to skip it; it also goes away when you start your next session.
- The "time's up" notification has a **Start 5-min Break** button.

During a break the menu-bar icon becomes a coffee cup. ▲▼ and Pause still work, and **End Break** stops it.
Breaks are **not** counted as focus time. You get a "Break's over" notification when it ends.

## Reports

Click **Report** at the bottom of the popover (or press ⌘R there).

- Ranges: Today, Yesterday, This Week, Last Week, This Month, Last Month, All Time
- Totals: focused time, number of sessions, completed sessions, average per active day
- **By tag**: time and % per tag. A session with several tags has its time split evenly so totals add up.
- **By day** chart, stacked by tag (by month for long ranges)
- Session list: right-click (or Delete key) to remove a session; ⏹ marks sessions finished early
- **Copy Summary**: paste a text summary into Slack, email, or a timesheet
- **Export CSV**: start, end, focused minutes, planned minutes, completed, tags, note

## Settings

Gear menu in the popover: **Launch at Login**, **Quit**.

## Your data

Sessions are stored locally in `~/Library/Application Support/Tock/sessions.json`.
Nothing is sent anywhere.

## Project layout

| File | What it does |
|---|---|
| `Sources/App.swift` | App entry, menu-bar icon, popover, report window, ⌃⌥T hotkey, notifications |
| `Sources/TimerEngine.swift` | Countdown, pause/resume, ±time, breaks, logging |
| `Sources/PopoverView.swift` | The menu-bar popover UI |
| `Sources/ReportView.swift` | The report window, CSV export, copy summary |
| `Sources/Model.swift` | Session data, `#tag`/duration parser, time formatting |
| `Sources/Store.swift` | Saves and loads sessions |
| `build.sh` | Builds and optionally installs the app |

## License

MIT — see [LICENSE](LICENSE).
